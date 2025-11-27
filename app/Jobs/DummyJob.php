<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class DummyJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public $company;
    public $queueName;

    /**
     * Create a new job instance.
     */
    public function __construct($company, $queueName)
    {
        $this->company = $company;
        $this->queueName = $queueName;
        $this->onQueue($queueName);
    }

    /**
     * Execute the job.
     */
    public function handle(): void
    {
        // Simulate some work
        usleep(rand(10000, 50000)); // 10-50ms
        Log::info("Processed job for {$this->company} on queue {$this->queueName}");
    }
}
