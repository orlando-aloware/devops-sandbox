# Laravel Horizon + Grafana Cloud Observability Demo

This project demonstrates a simple Laravel application using Laravel Horizon for queue management, with logs and metrics shipped to Grafana Cloud via Grafana Agent.

## Features

- **Laravel Horizon**: Manages Redis queues.
- **Redis**: Used as the queue driver (running in Docker).
- **Grafana Agent**: Ships application logs and custom metrics to Grafana Cloud (running in Docker).
- **Custom Metrics**: Exposes a simple metric endpoint for Prometheus scraping.
- **Structured Logging**: Application logs are formatted as JSON for better querying in Loki.
- **Simulated Scenarios**: Endpoints to dispatch successful jobs and simulate job failures.

## Prerequisites

- PHP 8.2+
- Composer
- Docker & Docker Compose
- A Grafana Cloud Account (Free tier works)

## Installation & Setup

1.  **Clone the repository**
    ```bash
    git clone <repository-url>
    cd grafanaHorizon
    ```

2.  **Install PHP Dependencies**
    ```bash
    composer install
    ```

3.  **Environment Configuration**
    Copy the example environment file and generate the application key:
    ```bash
    cp .env.example .env
    php artisan key:generate
    ```
    
    Ensure your `.env` is configured for Redis and JSON logging (already set if you cloned this repo, but double-check):
    ```dotenv
    QUEUE_CONNECTION=redis
    LOG_CHANNEL=json
    REDIS_HOST=127.0.0.1
    ```

4.  **Grafana Agent Configuration**
    Open `agent-config.yaml` in the root directory. You **MUST** update this file with your Grafana Cloud credentials.
    
    Replace the following placeholders:
    - `YOUR_PROMETHEUS_URL` (e.g., `https://prometheus-prod-xx-xx.grafana.net/api/prom/push`)
    - `YOUR_PROMETHEUS_USER` (User ID)
    - `YOUR_PROMETHEUS_PASSWORD` (API Key / Access Policy Token)
    - `YOUR_LOKI_URL` (e.g., `https://logs-prod-xx-xx.grafana.net/loki/api/v1/push`)
    - `YOUR_LOKI_USER` (User ID)
    - `YOUR_LOKI_PASSWORD` (API Key / Access Policy Token)

## Running the Application

1.  **Start Infrastructure (Redis + Grafana Agent)**
    Use Docker Compose to bring up the required services.
    ```bash
    docker-compose up -d
    ```

2.  **Start Laravel Development Server**
    In a new terminal window:
    ```bash
    php artisan serve
    ```
    The app will run at `http://localhost:8000`.

3.  **Start Laravel Horizon**
    In another terminal window, start the queue worker:
    ```bash
    php artisan horizon
    ```
    Access the Horizon dashboard at `http://localhost:8000/horizon`.

## Usage & Testing

Use the following endpoints to generate traffic and logs:

- **Dispatch a Job**: 
  `GET http://localhost:8000/dispatch`
  - Queues a `ProcessJob`.
  - Increments the `jobs_dispatched_total` metric.
  - Logs "Job processing started/finished".

- **Simulate a Failure**: 
  `GET http://localhost:8000/fail`
  - Queues a `FailJob` that throws an exception.
  - Logs an error which will appear in Grafana.
  - Visible in Horizon "Failed Jobs".

- **View Raw Metrics**: 
  `GET http://localhost:8000/metrics`
  - Shows the raw Prometheus-formatted metrics.

## Grafana Cloud Dashboard

To visualize the data in Grafana Cloud:

1.  **Verify Data**: Use "Explore" in Grafana to check:
    - **Loki**: Query `{job="laravel"}` to see logs.
    - **Prometheus**: Query `jobs_dispatched_total` to see metrics.

2.  **Create Dashboard**:
    - **Job Rate Panel**: Time series visualization with query `rate(jobs_dispatched_total[1m])`.
    - **Logs Panel**: Logs visualization with query `{job="laravel"}`.
    - **Errors Panel**: Logs visualization with query `{job="laravel"} |= "error"`.

### Dashboards
 - https://learningaquaware.grafana.net/public-dashboards/441fca3445e24e1e8146e379b2c26e37
 - https://learningaquaware.grafana.net/public-dashboards/46a4015d579b44fdbed97d8133cb9a35
 - https://learningaquaware.grafana.net/public-dashboards/59a1fd427cec4397bbb5fdb46bdba486
 
