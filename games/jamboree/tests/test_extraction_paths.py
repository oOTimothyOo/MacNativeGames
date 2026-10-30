"""Exercise the actual C# path guard without LibHac, game data or package feeds."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which('dotnet'), 'requires .NET SDK 10')
class ExtractionPathTests(unittest.TestCase):
    def test_rejects_traversal_and_host_symlinks(self):
        game = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='jamboree-path-tests-') as temporary:
            work = Path(temporary).resolve()
            shutil.copy2(game / 'runtime/tools/nx_extract/ExtractionPaths.cs', work)
            shutil.copy2(game / 'tests/extraction_paths.cs', work)
            project = work / 'PathTests.csproj'
            project.write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
                               '<OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework>'
                               '</PropertyGroup></Project>')
            config = work / 'NuGet.Config'
            config.write_text('<configuration><packageSources><clear /></packageSources>'
                              '<fallbackPackageFolders><clear /></fallbackPackageFolders></configuration>')
            env = dict(os.environ, DOTNET_CLI_HOME=str(work / 'dotnet'),
                       NUGET_PACKAGES=str(work / 'packages'), DOTNET_CLI_TELEMETRY_OPTOUT='1',
                       DOTNET_GENERATE_ASPNET_CERTIFICATE='false', DOTNET_EnableDiagnostics='0',
                       DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE='true')
            commands = [
                ['dotnet', 'restore', str(project), '--configfile', str(config), '-p:NuGetAudit=false'],
                ['dotnet', 'build', str(project), '--no-restore', '--disable-build-servers',
                 '-p:UseSharedCompilation=false'],
                ['dotnet', str(work / 'bin/Debug/net10.0/PathTests.dll'), str(work)],
            ]
            for command in commands:
                result = subprocess.run(command, cwd=work, env=env, capture_output=True, text=True, timeout=120)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('checks passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
