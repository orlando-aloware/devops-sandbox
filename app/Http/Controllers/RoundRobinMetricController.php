<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RoundRobinMetricController extends Controller
{
    public function development(): JsonResponse
    {
        return response()->json($this->generateMetrics('development'));
    }

    public function staging(): JsonResponse
    {
        return response()->json($this->generateMetrics('staging'));
    }

    public function production(): JsonResponse
    {
        return response()->json($this->generateMetrics('production'));
    }

    public function generateMetrics(string $environment): array
    {
        $companies = ['TechCorp', 'BizSolutions', 'InnovateLtd', 'AlphaOmega'];
        $queues = ['emails', 'reports', 'webhooks', 'notifications'];
        $metrics = [];

        // Multiplier to make production numbers look bigger/different
        $multiplier = match ($environment) {
            'production' => 100,
            'staging' => 10,
            default => 1,
        };

        foreach ($companies as $company) {
            foreach ($queues as $queue) {
                $metrics[] = [
                    'environment' => $environment,
                    'company' => $company,
                    'queue_name' => $queue,
                    'full_queue_name' => "{$environment}_{$company}_{$queue}",
                    'pending_jobs' => rand(0, 50 * $multiplier),
                    'processed_jobs' => rand(100, 1000 * $multiplier),
                    'failed_jobs' => rand(0, 5 * $multiplier),
                    'active_workers' => rand(1, 10),
                    'latency_ms' => rand(20, 500),
                    'timestamp' => now()->toIso8601String(),
                ];
            }
        }

        return $metrics;
    }
}
