import configparser
import json
import shlex
from pathlib import Path

from django.test import SimpleTestCase

from core.settings import BASE_DIR


class SQLiteDeploymentConfigurationTest(SimpleTestCase):
    def test_supervisor_runs_one_web_worker_and_independent_schedulers(self):
        supervisor = self._supervisor_config()
        self.assertEqual(
            {
                section
                for section in supervisor.sections()
                if section.startswith('program:')
            },
            {
                'program:web',
                'program:backup-scheduler',
                'program:import-preview-purge',
            },
        )
        web_command = shlex.split(supervisor['program:web']['command'])
        scheduler_command = shlex.split(
            supervisor['program:backup-scheduler']['command']
        )
        purge_command = shlex.split(
            supervisor['program:import-preview-purge']['command']
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
        self.assertEqual(
            purge_command,
            ['python', 'manage.py', 'run_import_preview_purge_scheduler'],
        )

    def test_supervisor_keeps_all_processes_running_and_forwards_signals(self):
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
        for section_name in (
            'program:web',
            'program:backup-scheduler',
            'program:import-preview-purge',
        ):
            with self.subTest(section=section_name):
                self.assertEqual(
                    dict(supervisor[section_name]),
                    {
                        'command': supervisor[section_name]['command'],
                        **expected_process_settings,
                    },
                )

    def test_wsgi_never_runs_migrations(self):
        source = Path(BASE_DIR, 'core', 'wsgi.py').read_text(encoding='utf-8')

        self.assertNotIn('call_command', source)
        self.assertNotIn("'migrate'", source)
        self.assertNotIn('gunicorn', source.lower())

    def test_start_script_is_fail_fast_before_supervisor(self):
        script_path = Path(BASE_DIR, 'deploy', 'start.sh')

        self.assertTrue(script_path.is_file())
        script_bytes = script_path.read_bytes()
        self.assertTrue(script_bytes.startswith(b'#!/bin/sh\n'))
        self.assertNotIn(b'\r', script_bytes)
        self.assertTrue(script_bytes.endswith(b'\n'))
        source = script_bytes.decode('utf-8')
        self.assertEqual(
            [line for line in source.splitlines() if line and not line.startswith('#')],
            [
                'set -eu',
                'python manage.py prepare_deploy',
                'exec supervisord -c /app/deploy/supervisord.conf',
            ],
        )

    def test_start_script_is_normalized_to_lf(self):
        attributes_path = Path(BASE_DIR, '.gitattributes')

        self.assertTrue(attributes_path.is_file())
        self.assertEqual(
            attributes_path.read_text(encoding='utf-8').splitlines(),
            ['deploy/start.sh text eol=lf'],
        )

    def test_docker_image_runs_fail_fast_entrypoint_as_pid_one(self):
        dockerfile_lines = Path(BASE_DIR, 'Dockerfile').read_text(
            encoding='utf-8'
        ).splitlines()
        stages = self._docker_stages(dockerfile_lines)
        self.assertEqual(len(stages), 2)
        build_instructions, runtime_instructions = stages
        protected_prefixes = ('ARG APP_VERSION', 'ENV APP_VERSION', 'LABEL ', 'CMD ')
        self.assertFalse(
            any(
                instruction.startswith(protected_prefixes)
                or instruction == 'RUN chmod 0755 /app/deploy/start.sh'
                for instruction in build_instructions
            )
        )
        instructions = runtime_instructions
        command_lines = [
            line for line in instructions if line.upper().startswith('CMD ')
        ]

        self.assertEqual(len(command_lines), 1)
        self.assertEqual(
            json.loads(command_lines[0].split(maxsplit=1)[1]),
            ['/app/deploy/start.sh'],
        )
        self.assertIn('ARG APP_VERSION=development', instructions)
        self.assertIn('ENV APP_VERSION=${APP_VERSION}', instructions)
        self.assertIn(
            'LABEL org.opencontainers.image.revision=${APP_VERSION}',
            instructions,
        )
        self.assertIn(
            'RUN chmod 0755 /app/deploy/start.sh',
            instructions,
        )
        expected_runtime_sequence = [
            'COPY . .',
            'ARG APP_VERSION=development',
            'ENV APP_VERSION=${APP_VERSION}',
            'LABEL org.opencontainers.image.revision=${APP_VERSION}',
            'RUN chmod 0755 /app/deploy/start.sh',
            'CMD ["/app/deploy/start.sh"]',
        ]
        for instruction in expected_runtime_sequence[1:]:
            with self.subTest(instruction=instruction):
                self.assertEqual(instructions.count(instruction), 1)
        positions = [instructions.index(item) for item in expected_runtime_sequence]
        self.assertEqual(positions, sorted(positions))

    def test_compose_web_service_inherits_the_image_command(self):
        compose_lines = Path(BASE_DIR, 'docker-compose.yml').read_text(
            encoding='utf-8'
        ).splitlines()
        web_service_lines = self._yaml_mapping_body(
            compose_lines,
            key='web',
            indentation=2,
        )
        web_service_keys = self._yaml_mapping_keys(
            web_service_lines,
            indentation=4,
        )

        self.assertTrue({'command', 'entrypoint'}.isdisjoint(web_service_keys))

    def test_ci_builds_the_production_image_after_django_checks(self):
        workflow_lines = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
            encoding='utf-8'
        ).splitlines()
        jobs_lines = self._yaml_mapping_body(
            workflow_lines,
            key='jobs',
            indentation=0,
        )
        django_job_lines = self._yaml_mapping_body(
            jobs_lines,
            key='django',
            indentation=2,
        )
        steps = self._yaml_sequence_mappings(
            django_job_lines,
            key='steps',
            indentation=4,
        )
        step_names = [step['name'] for step in steps]
        build_name = 'Build production image'

        self.assertIn(build_name, step_names)
        self.assertGreater(
            step_names.index(build_name),
            step_names.index('Coverage gate'),
        )
        build_step = next(step for step in steps if step['name'] == build_name)
        self.assertEqual(
            build_step['run'],
            '>-',
        )
        source = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
            encoding='utf-8'
        )
        self.assertIn('--build-arg APP_VERSION=${{ github.sha }}', source)
        self.assertIn('--tag lar-finance-ci:${{ github.sha }} .', source)

    def test_ci_smokes_the_pinned_supervisor_version_after_build(self):
        workflow_lines = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
            encoding='utf-8'
        ).splitlines()
        jobs_lines = self._yaml_mapping_body(
            workflow_lines,
            key='jobs',
            indentation=0,
        )
        django_job_lines = self._yaml_mapping_body(
            jobs_lines,
            key='django',
            indentation=2,
        )
        steps = self._yaml_sequence_mappings(
            django_job_lines,
            key='steps',
            indentation=4,
        )
        step_names = [step['name'] for step in steps]
        build_name = 'Build production image'
        smoke_name = 'Verify Supervisor version'

        self.assertIn(smoke_name, step_names)
        self.assertGreater(step_names.index(smoke_name), step_names.index(build_name))
        smoke_step = next(step for step in steps if step['name'] == smoke_name)
        self.assertEqual(
            smoke_step['run'],
            'test "$(docker run --rm lar-finance-ci:${{ github.sha }} '
            'supervisord --version)" = "4.3.0"',
        )

    def test_ci_smokes_immutable_health_and_all_supervisor_processes(self):
        source = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
            encoding='utf-8'
        )
        required_fragments = (
            'name: Smoke immutable startup and process topology',
            'docker volume create lar-finance-ci-data',
            'trap cleanup EXIT',
            '--volume lar-finance-ci-data:/app/data',
            '--env R2_BACKUP_ENDPOINT_URL=https://example.invalid',
            "'version': os.environ['GITHUB_SHA']",
            'docker top lar-finance-ci-smoke -eo pid,args > processes.txt',
            "grep -F 'gunicorn core.wsgi:application' processes.txt",
            "grep -F 'python manage.py run_backup_scheduler' processes.txt",
            "grep -F 'python manage.py run_import_preview_purge_scheduler' "
            'processes.txt',
        )
        for fragment in required_fragments:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, source)
        self.assertLess(
            source.index('trap cleanup EXIT'),
            source.index('docker volume create lar-finance-ci-data'),
        )
        self.assertNotIn('r2.cloudflarestorage.com', source)

    def test_publish_job_requires_all_six_quality_jobs_and_release_tag(self):
        publish = self._workflow_job('publish_image')
        self.assertEqual(
            set(publish['needs']),
            {
                'django',
                'secrets',
                'flutter_checks',
                'flutter_windows',
                'flutter_android',
                'flutter_ios',
            },
        )
        self.assertEqual(
            publish['if'],
            "startsWith(github.ref, 'refs/tags/v')",
        )
        self.assertEqual(publish['permissions']['packages'], 'write')
        self.assertEqual(publish['permissions']['contents'], 'read')

        source = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
            encoding='utf-8'
        )
        self.assertIn('--build-arg APP_VERSION="${GITHUB_SHA}"', source)
        self.assertIn(':sha-${GITHUB_SHA}', source)
        self.assertIn(':${GITHUB_REF_NAME}', source)
        self.assertIn('password: ${{ secrets.GITHUB_TOKEN }}', source)
        self.assertNotRegex(source, r'ghp_[A-Za-z0-9]{20,}')
        self.assertNotRegex(source, r'github_pat_[A-Za-z0-9_]{20,}')

    def test_workflow_job_parser_rejects_job_text_inside_block_scalar(self):
        workflow_lines = [
            'jobs:',
            '  django:',
            '    steps:',
            '      - name: Explain',
            '        run: |',
            '          publish_image:',
            '            permissions:',
            '              packages: write',
        ]

        with self.assertRaises(ValueError):
            self._workflow_job('publish_image', lines=workflow_lines)

    def test_yaml_step_parser_ignores_list_items_inside_block_scalars(self):
        workflow_lines = [
            'jobs:',
            '  django:',
            '    steps:',
            '      - name: Tests',
            '        run: |',
            '          echo running tests',
            '          - name: Build production image',
            '            run: docker build --tag fake .',
        ]

        self.assertEqual(
            self._yaml_sequence_mappings(
                workflow_lines,
                key='steps',
                indentation=4,
            ),
            [{'name': 'Tests', 'run': '|'}],
        )

    def test_yaml_mapping_parser_normalizes_quoted_keys(self):
        compose_lines = [
            'services:',
            '  web:',
            '    "command": gunicorn core.wsgi:application',
        ]
        web_service_lines = self._yaml_mapping_body(
            compose_lines,
            key='web',
            indentation=2,
        )

        self.assertEqual(
            self._yaml_mapping_keys(web_service_lines, indentation=4),
            {'command'},
        )

    @staticmethod
    def _supervisor_config():
        supervisor = configparser.RawConfigParser(interpolation=None)
        config_path = Path(BASE_DIR, 'deploy', 'supervisord.conf')
        with config_path.open(encoding='utf-8') as file:
            supervisor.read_file(file)
        return supervisor

    @staticmethod
    def _docker_stages(lines):
        stages = []
        current_stage = None
        for line in lines:
            instruction = line.strip()
            if not instruction or instruction.startswith('#'):
                continue
            if instruction.upper().startswith('FROM '):
                current_stage = []
                stages.append(current_stage)
            elif current_stage is not None:
                current_stage.append(instruction)
        return stages

    @classmethod
    def _workflow_job(cls, job_name, *, lines=None):
        if lines is None:
            lines = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
                encoding='utf-8'
            ).splitlines()
        jobs_lines = cls._yaml_mapping_body(lines, key='jobs', indentation=0)
        try:
            job_lines = cls._yaml_mapping_body(
                jobs_lines,
                key=job_name,
                indentation=2,
            )
        except StopIteration as error:
            raise ValueError(f'Workflow job not found: {job_name}') from error

        job = cls._yaml_scalar_mapping(job_lines, indentation=4)
        job['needs'] = cls._yaml_sequence_values(
            job_lines,
            key='needs',
            indentation=4,
        )
        permissions_lines = cls._yaml_mapping_body(
            job_lines,
            key='permissions',
            indentation=4,
        )
        job['permissions'] = cls._yaml_scalar_mapping(
            permissions_lines,
            indentation=6,
        )
        return job

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

    @staticmethod
    def _yaml_mapping_keys(lines, *, indentation):
        return {
            SQLiteDeploymentConfigurationTest._yaml_key_value(line.strip())[0]
            for line in lines
            if (
                len(line) - len(line.lstrip()) == indentation
                and ':' in line
                and not line.lstrip().startswith(('#', '- '))
            )
        }

    @classmethod
    def _yaml_scalar_mapping(cls, lines, *, indentation):
        result = {}
        for line in lines:
            stripped = line.strip()
            if (
                len(line) - len(line.lstrip()) == indentation
                and ':' in stripped
                and not stripped.startswith(('#', '- '))
            ):
                key, value = cls._yaml_key_value(stripped)
                if value and value not in ('|', '|-', '>', '>-'):
                    result[key] = cls._yaml_scalar(value)
        return result

    @classmethod
    def _yaml_sequence_values(cls, lines, *, key, indentation):
        body = cls._yaml_mapping_body(lines, key=key, indentation=indentation)
        item_indentation = indentation + 2
        return [
            cls._yaml_scalar(line.strip().removeprefix('- '))
            for line in body
            if (
                len(line) - len(line.lstrip()) == item_indentation
                and line.strip().startswith('- ')
            )
        ]

    @classmethod
    def _yaml_sequence_mappings(cls, lines, *, key, indentation):
        body = cls._yaml_mapping_body(lines, key=key, indentation=indentation)
        entries = []
        entry = None
        item_indentation = indentation + 2
        field_indentation = item_indentation + 2

        for line in body:
            stripped = line.strip()
            current_indentation = len(line) - len(line.lstrip())
            if current_indentation == item_indentation and stripped.startswith('- '):
                if entry is not None:
                    entries.append(entry)
                entry = {}
                field, value = cls._yaml_key_value(stripped.removeprefix('- '))
                entry[field] = value
            elif (
                entry is not None
                and current_indentation == field_indentation
                and ':' in stripped
                and not stripped.startswith(('#', '- '))
            ):
                field, value = cls._yaml_key_value(stripped)
                entry[field] = value

        if entry is not None:
            entries.append(entry)

        return entries

    @staticmethod
    def _yaml_key_value(text):
        raw_key, separator, value = text.partition(':')
        if not separator:
            raise ValueError(f'Expected a YAML key/value pair: {text!r}')

        key = raw_key.strip()
        if key.startswith('"') and key.endswith('"'):
            key = json.loads(key)
        elif key.startswith("'") and key.endswith("'"):
            key = key[1:-1].replace("''", "'")

        return key, value.strip()

    @staticmethod
    def _yaml_scalar(value):
        if value.startswith('"') and value.endswith('"'):
            return json.loads(value)
        if value.startswith("'") and value.endswith("'"):
            return value[1:-1].replace("''", "'")
        return value
