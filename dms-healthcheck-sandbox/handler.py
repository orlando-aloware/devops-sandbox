"""
DMS Healthcheck Lambda Function

Reusable logic for checking and recovering tables in DMS error state.

Mode resolution (highest priority first):
  1. Event payload key "mode"        — overrides for one-off CLI invocations
  2. Environment variable MODE        — controls the scheduled nightly default
  3. Falls back to: ALERT

Supported modes:
  ALERT   — check tables, send SNS email if any are in error state  (nightly EventBridge default)
  CHECK   — return JSON list of errored tables, no side-effects      (safe dry-run)
  RELOAD  — stop the DMS task, wait until stopped, restart reload-target

Required environment variables:
  DMS_TASK_ARN   — full ARN of the DMS replication task
  SNS_TOPIC_ARN  — SNS topic ARN for alert emails
  MODE           — default mode: ALERT | CHECK | RELOAD  (defaults to ALERT)

Optional:
  AWS_REGION     — defaults to us-west-2
"""

import os
import time
from datetime import datetime, timezone

import boto3

DMS_TASK_ARN  = os.environ['DMS_TASK_ARN']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
AWS_REGION    = os.environ.get('AWS_REGION', 'us-west-2')
DEFAULT_MODE  = os.environ.get('MODE', 'ALERT').upper()


def get_errored_tables() -> list[str]:
    """Return a list of 'schema.table' strings currently in 'Table error' state."""
    dms      = boto3.client('dms', region_name=AWS_REGION)
    errored  = []
    kwargs   = {'ReplicationTaskArn': DMS_TASK_ARN, 'MaxRecords': 500}

    while True:
        response = dms.describe_table_statistics(**kwargs)
        for table in response.get('TableStatistics', []):
            if table.get('TableState') == 'Table error':
                errored.append(f"{table['SchemaName']}.{table['TableName']}")

        marker = response.get('Marker')
        if not marker:
            break
        kwargs['Marker'] = marker

    return errored


def wait_for_task_stopped(dms_client, max_wait_seconds: int = 600) -> None:
    """Poll until the DMS task reaches 'stopped' status or raises on timeout/failure."""
    elapsed = 0
    while elapsed < max_wait_seconds:
        response = dms_client.describe_replication_tasks(
            Filters=[{'Name': 'replication-task-arn', 'Values': [DMS_TASK_ARN]}]
        )
        tasks = response.get('ReplicationTasks', [])
        if not tasks:
            raise RuntimeError('DMS task not found.')

        status = tasks[0].get('Status', '')
        print(f'[wait] DMS task status: {status} ({elapsed}s elapsed)')

        if status == 'stopped':
            return
        if status in ('failed', 'deleting'):
            raise RuntimeError(f'DMS task entered unexpected state: {status}')

        time.sleep(15)
        elapsed += 15

    raise TimeoutError(f'DMS task did not stop within {max_wait_seconds} seconds.')


def stop_and_reload_task() -> None:
    """Stop the DMS task and issue a full reload-target restart."""
    dms = boto3.client('dms', region_name=AWS_REGION)

    print('==> Stopping DMS task...')
    dms.stop_replication_task(ReplicationTaskArn=DMS_TASK_ARN)

    print('==> Waiting for DMS task to stop...')
    wait_for_task_stopped(dms)

    print('==> Starting DMS task (reload-target)...')
    dms.start_replication_task(
        ReplicationTaskArn=DMS_TASK_ARN,
        StartReplicationTaskType='reload-target',
    )
    print('==> DMS task reload initiated.')


def send_alert(errored_tables: list[str]) -> None:
    """Publish an SNS alert listing all errored tables with reload instructions."""
    sns        = boto3.client('sns', region_name=AWS_REGION)
    table_list = '\n'.join(f'  - {t}' for t in errored_tables)
    now        = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    fn         = 'dms-healthcheck'

    reload_cmd = (
        f'aws lambda invoke \\\n'
        f'  --function-name {fn} \\\n'
        f'  --profile staging --region {AWS_REGION} \\\n'
        f'  --payload \'{{"mode":"RELOAD"}}\' \\\n'
        f'  --cli-binary-format raw-in-base64-out \\\n'
        f'  response.json && cat response.json'
    )

    check_cmd = (
        f'aws lambda invoke \\\n'
        f'  --function-name {fn} \\\n'
        f'  --profile staging --region {AWS_REGION} \\\n'
        f'  --payload \'{{"mode":"CHECK"}}\' \\\n'
        f'  --cli-binary-format raw-in-base64-out \\\n'
        f'  response.json && cat response.json'
    )

    message = (
        f'[ALERT] DMS Table Errors Detected — Staging\n'
        f'{"=" * 60}\n\n'
        f'Task ARN : {DMS_TASK_ARN}\n'
        f'Detected : {now}\n\n'
        f'The following {len(errored_tables)} table(s) are in "Table error" state:\n\n'
        f'{table_list}\n\n'
        f'{"=" * 60}\n'
        f'HOW TO RECOVER\n'
        f'{"=" * 60}\n\n'
        f'Option A — Invoke Lambda directly (immediate, no confirmation prompt):\n\n'
        f'  {reload_cmd}\n\n'
        f'Option B — Jenkins pipeline (interactive confirmation before reload):\n\n'
        f'  1. Open Jenkins > dms-healthcheck pipeline\n'
        f'  2. Click "Build Now"\n'
        f'  3. Approve the reload prompt when it shows the errored tables\n\n'
        f'{"=" * 60}\n'
        f'DRY-RUN — re-check state without making any changes:\n\n'
        f'  {check_cmd}\n\n'
        f'{"=" * 60}\n'
        f'Note: Reloading stops the DMS task and restarts it with "reload-target".\n'
        f'Replication lag will catch up after restart. Plan for a brief Redshift data gap.\n'
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f'[ALERT] DMS Tables in Error State — {len(errored_tables)} table(s) — Staging',
        Message=message,
    )
    print(f'Alert sent to SNS topic for {len(errored_tables)} errored table(s).')


def handler(event: dict, context) -> dict:
    # Event payload key "mode" overrides the env var MODE for one-off invocations
    mode = event.get('mode', DEFAULT_MODE).upper()
    print(f'DMS healthcheck running in mode: {mode}  (env default: {DEFAULT_MODE})')

    if mode == 'CHECK':
        errored = get_errored_tables()
        print(f'Errored tables ({len(errored)}): {errored}')
        return {
            'statusCode': 200,
            'mode': 'CHECK',
            'has_errors': len(errored) > 0,
            'errored_tables': errored,
        }

    if mode == 'RELOAD':
        stop_and_reload_task()
        return {
            'statusCode': 200,
            'mode': 'RELOAD',
            'message': 'DMS task reload initiated successfully.',
        }

    if mode == 'ALERT':
        errored = get_errored_tables()
        if not errored:
            print('No DMS table errors detected. Nothing to alert.')
            return {
                'statusCode': 200,
                'mode': 'ALERT',
                'message': 'No DMS table errors detected.',
            }

        send_alert(errored)
        return {
            'statusCode': 200,
            'mode': 'ALERT',
            'message': f'Alert sent for {len(errored)} table(s) in error state.',
            'errored_tables': errored,
        }

    raise ValueError(f'Unknown mode: {mode!r}. Must be ALERT, CHECK, or RELOAD.')
