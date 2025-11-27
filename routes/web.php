<?php

use Illuminate\Support\Facades\Route;
use App\Jobs\ProcessJob;
use App\Jobs\FailJob;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Log;

Route::get('/', function () {
    return view('welcome');
});

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
    $count = Redis::get('jobs_dispatched_total') ?? 0;
    return response("jobs_dispatched_total $count\n", 200)
        ->header('Content-Type', 'text/plain');
});
