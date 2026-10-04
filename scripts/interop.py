"""Real UDP cross-implementation checks using aiocoap (test-only dependency)."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import socket

import aiocoap
import aiocoap.resource as resource

ROOT = Path(__file__).resolve().parents[1]


class Status(resource.Resource):
    async def render_get(self, request):
        return aiocoap.Message(code=aiocoap.CONTENT, payload=b'python-ready', content_format=0)


async def checks(client_binary):
    context = await aiocoap.Context.create_client_context(transports=['simple6'])
    outcomes = []
    try:
        async def send(path, code=aiocoap.GET, payload=b'', **options):
            request = aiocoap.Message(code=code, uri='coap://127.0.0.1:56830' + path, payload=payload, **options)
            return await asyncio.wait_for(context.request(request).response, 5)

        reply = await send('/status')
        assert reply.code == aiocoap.CONTENT and reply.payload == b'ready'
        outcomes.append('aiocoap GET -> MoonBit 2.05 Content')
        reply = await send('/.well-known/core')
        assert reply.opt.content_format == 40 and b'</status>' in reply.payload
        outcomes.append('RFC6690 discovery media type and links')
        reply = await send('/config')
        original_tag = reply.opt.etag
        assert original_tag
        reply = await send('/config', aiocoap.PUT, b'changed', if_match=(original_tag,), content_format=0)
        assert reply.code == aiocoap.CHANGED
        new_tag = reply.opt.etag
        reply = await send('/config', aiocoap.PUT, b'wrong', if_match=(original_tag,), content_format=0)
        assert reply.code == aiocoap.PRECONDITION_FAILED
        outcomes.append('conditional PUT succeeds once then rejects stale ETag')
        reply = await send('/config', etags=(new_tag,))
        assert reply.code == aiocoap.VALID and not reply.payload
        outcomes.append('ETag validation produces 2.03 Valid')
        reply = await send('/config', accept=50)
        assert reply.code == aiocoap.NOT_ACCEPTABLE
        outcomes.append('Accept mismatch returns 4.06')
        reply = await send('/separate')
        assert reply.code == aiocoap.CONTENT and reply.payload == b'deferred'
        outcomes.append('Empty ACK and separate CON response')
        reply = await send('/missing')
        assert reply.code == aiocoap.NOT_FOUND
        outcomes.append('missing route returns 4.04')

        # A raw peer sends the exact same POST twice over the same UDP socket.
        # This supplements aiocoap, which generates a new MID for new requests.
        def duplicate_post():
            # CON, TKL=1, POST, MID=4242, Token=x, Uri-Path=jobs, payload=create.
            packet = bytes.fromhex('4102109278b4') + b'jobs\xffcreate'
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.settimeout(3)
                sock.sendto(packet, ('127.0.0.1', 56830))
                first = sock.recv(65536)
                sock.sendto(packet, ('127.0.0.1', 56830))
                second = sock.recv(65536)
                assert first == second and first.endswith(b'\xff1')
        await asyncio.to_thread(duplicate_post)
        outcomes.append('duplicate POST replays identical bytes; business executes once')

        site = resource.Site()
        site.add_resource(['status'], Status())
        python_server = await aiocoap.Context.create_server_context(site, bind=('127.0.0.1', 56831), transports=['simplesocketserver'])
        try:
            process = await asyncio.create_subprocess_exec(str(client_binary), stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, cwd=ROOT)
            stdout, stderr = await asyncio.wait_for(process.communicate(), 10)
            assert process.returncode == 0, stderr.decode(errors='replace')
            assert b'2.05 python-ready' in stdout
            outcomes.append('MoonBit GET client -> aiocoap server')
        finally:
            await python_server.shutdown()
        return outcomes
    finally:
        await context.shutdown()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moon', default='moon')
    args = parser.parse_args()
    subprocess.run([args.moon, 'build', '--target', 'native', '--deny-warn'], cwd=ROOT, check=True)
    suffix = '.exe' if os.name == 'nt' else ''
    build = ROOT / '_build/native/debug/build/cmd'
    server_binary = build / 'interop_server' / ('interop_server' + suffix)
    client_binary = build / 'interop_client' / ('interop_client' + suffix)
    if not server_binary.is_file() or not client_binary.is_file():
        raise SystemExit(f'Expected native binaries missing under {build}')
    with subprocess.Popen([str(server_binary)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as server:
        try:
            # The server is our own finite test child. No unrelated processes are stopped.
            deadline = time.monotonic() + 5
            while True:
                if server.poll() is not None:
                    raise RuntimeError(server.stderr.read().decode(errors='replace'))
                try:
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                        sock.settimeout(.2)
                        sock.sendto(bytes.fromhex('40010001b6737461747573'), ('127.0.0.1', 56830))
                        sock.recv(65536)
                        break
                except (TimeoutError, ConnectionResetError):
                    if time.monotonic() >= deadline:
                        raise RuntimeError('MoonBit server startup timeout')
                    time.sleep(.05)
            results = asyncio.run(checks(client_binary))
            print(json.dumps({'status': 'passed', 'checks': results}, indent=2))
        finally:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


if __name__ == '__main__':
    main()
