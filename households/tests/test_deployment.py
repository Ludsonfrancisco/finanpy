import configparser
import json
import shlex
from pathlib import Path

from django.test import SimpleTestCase

from core.settings import BASE_DIR


class SQLiteDeploymentConfigurationTest(SimpleTestCase):
    def test_supervisor_runs_one_web_worker_and_backup_scheduler(self):
        supervisor = self._supervisor_config()
        web_command = shlex.split(supervisor['program:web']['command'])
        scheduler_command = shlex.split(
            supervisor['program:backup-scheduler']['command']
        )

        self.assertEqual(
            web_command,
            [
                'gunicorn',
                'core.wsgi:application',
                '--bind',
                '0.0.0.0:8000',
                '--workers',
                '1',
            ],
        )
        self.assertEqual(
            scheduler_command,
            ['python', 'manage.py', 'run_backup_scheduler'],
        )

    def test_supervisor_keeps_both_processes_running_and_forwards_signals(self):
        supervisor = self._supervisor_config()
        expected_process_settings = {
            'directory': '/app',
            'autostart': 'true',
            'autorestart': 'true',
            'startsecs': '5',
            'stopsignal': 'TERM',
            'stopasgroup': 'true',
            'killasgroup': 'true',
            'stdout_logfile': '/dev/fd/1',
            'stdout_logfile_maxbytes': '0',
            'stderr_logfile': '/dev/fd/2',
            'stderr_logfile_maxbytes': '0',
        }

        self.assertTrue(supervisor.getboolean('supervisord', 'nodaemon'))
        for section_name in ('program:web', 'program:backup-scheduler'):
            with self.subTest(section=section_name):
                self.assertEqual(
                    dict(supervisor[section_name]),
                    {
                        'command': supervisor[section_name]['command'],
                        **expected_process_settings,
                    },
                )

    def test_docker_image_starts_supervisor_as_pid_one(self):
        dockerfile_lines = Path(BASE_DIR, 'Dockerfile').read_text(
            encoding='utf-8'
        ).splitlines()
        instructions = [
            line.strip()
            for line in dockerfile_lines
            if line.strip() and not line.lstrip().startswith('#')
        ]
        command_lines = [
            line for line in instructions if line.upper().startswith('CMD ')
        ]

        self.assertEqual(len(command_lines), 1)
        self.assertEqual(
            json.loads(command_lines[0].split(maxsplit=1)[1]),
            ['supervisord', '-c', '/app/deploy/supervisord.conf'],
        )

    def test_compose_web_service_inherits_the_image_command(self):
        compose_lines = Path(BASE_DIR, 'docker-compose.yml').read_text(
            encoding='utf-8'
        ).splitlines()
        web_service_lines = self._yaml_mapping_body(
            compose_lines,
            key='web',
            indentation=2,
        )
        web_service_keys = {
            line.strip().split(':', maxsplit=1)[0]
            for line in web_service_lines
            if len(line) - len(line.lstrip()) == 4 and ':' in line
        }

        self.assertNotIn('command', web_service_keys)

    def test_ci_builds_the_production_image_after_django_checks(self):
        workflow_lines = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
            encoding='utf-8'
        ).splitlines()
        django_job_lines = self._yaml_mapping_body(
            workflow_lines,
            key='django',
            indentation=2,
        )
        step_names = [
            line.strip().removeprefix('- name:').strip()
            for line in django_job_lines
            if line.strip().startswith('- name:')
        ]
        build_name = 'Build production image'

        self.assertIn(build_name, step_names)
        self.assertGreater(step_names.index(build_name), step_names.index('Coverage gate'))
        build_name_index = next(
            index
            for index, line in enumerate(django_job_lines)
            if line.strip() == f'- name: {build_name}'
        )
        self.assertEqual(
            django_job_lines[build_name_index + 1].strip(),
            'run: docker build --tag lar-finance-ci:${{ github.sha }} .',
        )

    @staticmethod
    def _supervisor_config():
        supervisor = configparser.RawConfigParser(interpolation=None)
        with Path(BASE_DIR, 'deploy', 'supervisord.conf').open(encoding='utf-8') as file:
            supervisor.read_file(file)
        return supervisor

    @staticmethod
    def _yaml_mapping_body(lines, *, key, indentation):
        key_line = f'{" " * indentation}{key}:'
        start_index = next(
            index for index, line in enumerate(lines) if line == key_line
        )
        body = []

        for line in lines[start_index + 1 :]:
            stripped = line.strip()
            if stripped and not stripped.startswith('#'):
                current_indentation = len(line) - len(line.lstrip())
                if current_indentation <= indentation:
                    break
            body.append(line)

        return body
