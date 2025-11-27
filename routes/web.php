<?php

use Illuminate\Support\Facades\Route;
use App\Jobs\ProcessJob;
use App\Jobs\FailJob;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Log;

use App\Http\Controllers\RoundRobinMetricController;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/metrics/rr-queue/development', [RoundRobinMetricController::class, 'development']);
Route::get('/metrics/rr-queue/staging', [RoundRobinMetricController::class, 'staging']);
Route::get('/metrics/rr-queue/production', [RoundRobinMetricController::class, 'production']);

Route::get('/dispatch', function () {
    ProcessJob::dispatch();
    Redis::incr('jobs_dispatched_total');
    Log::info('Job dispatched via endpoint');
    return 'Job dispatched';
});

Route::get('/fail', function () {
    FailJob::dispatch();
    Log::info('Failing job dispatched via endpoint');
    return 'Failing job dispatched';
});

Route::get('/metrics', function () {
    $output = "";

    // Existing Redis Metric
    $count = Redis::get('jobs_dispatched_total') ?? 0;
    $output .= "jobs_dispatched_total $count\n";

    // Round Robin Metrics
    $controller = new RoundRobinMetricController();
    $environments = ['development', 'staging', 'production'];

    foreach ($environments as $env) {
        $metrics = $controller->generateMetrics($env);
        foreach ($metrics as $m) {
            $output .= "rr_pending_jobs{environment=\"$env\",company=\"{$m['company']}\",queue=\"{$m['queue_name']}\"} {$m['pending_jobs']}\n";
            $output .= "rr_processed_jobs{environment=\"$env\",company=\"{$m['company']}\",queue=\"{$m['queue_name']}\"} {$m['processed_jobs']}\n";
            $output .= "rr_failed_jobs{environment=\"$env\",company=\"{$m['company']}\",queue=\"{$m['queue_name']}\"} {$m['failed_jobs']}\n";
            $output .= "rr_active_workers{environment=\"$env\",company=\"{$m['company']}\",queue=\"{$m['queue_name']}\"} {$m['active_workers']}\n";
            $output .= "rr_latency_ms{environment=\"$env\",company=\"{$m['company']}\",queue=\"{$m['queue_name']}\"} {$m['latency_ms']}\n";
        }
    }

    return response($output, 200)
        ->header('Content-Type', 'text/plain');
});
