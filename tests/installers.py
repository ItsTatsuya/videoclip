"""Offline installer integration checks; run with Python 3 from any directory."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)


def verify(config):
    assert (config / 'scripts/videoclip/main.lua').is_file()
    assert (config / 'scripts/videoclip/videoclip/main.lua').is_file()
    assert (config / 'script-opts/videoclip.conf').is_file()


def psquote(value):
    return "'" + str(value).replace("'", "''") + "'"


def shellpath(value):
    value = Path(value).as_posix()
    if os.name == 'nt' and value[1:3] == ':/':
        return '/' + value[0].lower() + value[2:]
    return value


def main():
    with tempfile.TemporaryDirectory(prefix='videoclip-install-tests-') as work:
        work = Path(work)
        archive = work / 'source.zip'
        tarball = work / 'source.tar.gz'
        files = [ROOT / 'main.lua', ROOT / 'LICENSE'] + list((ROOT / 'videoclip').rglob('*'))
        with zipfile.ZipFile(archive, 'w') as zipped, tarfile.open(tarball, 'w:gz') as tar:
            for path in files:
                if path.is_file():
                    name = 'videoclip-master/' + path.relative_to(ROOT).as_posix()
                    zipped.write(path, name)
                    tar.add(path, arcname=name)

        powershell = shutil.which('powershell') or shutil.which('pwsh')
        if powershell:
            config = work / 'PS config & spaces'
            script = ROOT / 'docs/install.ps1'
            prelude = "function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing); Copy-Item -LiteralPath " + psquote(archive) + " -Destination $OutFile }\n"

            def install(fail=False):
                stub = "function Invoke-WebRequest { throw 'Simulated network failure' }\n" if fail else prelude
                command = "$ErrorActionPreference='Stop'\n" + stub + '& ' + psquote(script) + ' -ConfigDir ' + psquote(config) + ' -SkipFfmpeg'
                if fail:
                    command = "$ErrorActionPreference='Stop'\n" + stub + "try { & " + psquote(script) + ' -ConfigDir ' + psquote(config) + ' -SkipFfmpeg' + "; throw 'Expected rejection' } catch { if ($_.Exception.Message -eq 'Expected rejection') { throw }; Write-Output 'Expected installer rejection' }"
                run([powershell, '-NoProfile', '-NonInteractive', '-Command', command])

            install()
            verify(config)
            settings = config / 'script-opts/videoclip.conf'
            settings.write_text('# preserved\n')
            old = config / 'scripts/videoclip/old-version.txt'
            old.write_text('previous plugin')
            install()
            assert settings.read_text() == '# preserved\n'
            assert not old.exists()
            assert list((config / 'videoclip-backups').rglob('old-version.txt'))
            before = (config / 'scripts/videoclip/main.lua').read_bytes()
            install(fail=True)
            assert before == (config / 'scripts/videoclip/main.lua').read_bytes()
            # A Git-managed install must remain untouched.
            (config / 'scripts/videoclip/.git').mkdir()
            install(fail=True)
            assert before == (config / 'scripts/videoclip/main.lua').read_bytes()
            print('PowerShell: fresh install, update, backups, preferences, failed download, Git protection passed.')
        else:
            print('PowerShell tests skipped: runtime unavailable.')

        shell = shutil.which('bash')
        if os.name == 'nt':
            candidate = Path('C:/Program Files/Git/bin/bash.exe')
            shell = str(candidate) if candidate.exists() else None
        if shell:
            config = work / 'shell config & spaces'
            command = 'sh ' + shlex.quote(shellpath(ROOT / 'docs/install.sh')) + ' ' + shlex.quote(shellpath(config))
            # The installer runs without Git; curl is replaced with a local fixture.
            mock = work / 'mock'
            mock.mkdir()
            curl = mock / 'curl'
            curl.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n if [ "$1" = "-o" ]; then cp ' + shlex.quote(shellpath(tarball)) + ' "$2"; exit; fi\n shift\ndone\nexit 1\n')
            curl.chmod(0o755)
            prefix = 'set -eu\nPATH=' + shlex.quote(shellpath(mock)) + ':"$PATH"\nexport PATH\n'
            run([shell, '--noprofile', '--norc'], input=prefix + command)
            verify(config)
            settings = config / 'script-opts/videoclip.conf'
            settings.write_text('# preserved\n')
            (config / 'scripts/videoclip/old-version.txt').write_text('previous plugin')
            run([shell, '--noprofile', '--norc'], input=prefix + command)
            assert settings.read_text() == '# preserved\n'
            assert list((config / 'videoclip-backups').rglob('old-version.txt'))
            before = (config / 'scripts/videoclip/main.lua').read_bytes()
            curl.write_text('#!/bin/sh\nexit 22\n')
            run([shell, '--noprofile', '--norc'], input=prefix + 'if ' + command + '; then exit 1; fi')
            assert before == (config / 'scripts/videoclip/main.lua').read_bytes()
            (config / 'scripts/videoclip/.git').mkdir()
            run([shell, '--noprofile', '--norc'], input=prefix + 'if ' + command + '; then exit 1; fi')
            assert before == (config / 'scripts/videoclip/main.lua').read_bytes()
            print('Shell: fresh install, update, backups, preferences, failed download, Git protection passed.')
        else:
            print('Shell tests skipped: runtime unavailable.')


if __name__ == '__main__':
    main()
