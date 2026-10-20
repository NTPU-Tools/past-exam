#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

for command_name in docker git curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required (docker compose)." >&2
  exit 1
fi

echo "=== NTPU Past Exam — Local Dev Bootstrap ==="
echo ""

backend_port="${BACKEND_PORT:-8080}"
frontend_port="${FRONTEND_PORT:-5173}"
s3_console_port="${S3_CONSOLE_PORT:-9001}"

# --- Clone sub-repos if missing ---
if [ ! -d "ntpu-past-exam" ]; then
  echo "Cloning frontend..."
  git clone git@github.com:NTPU-Tools/ntpu-past-exam.git
else
  echo "Frontend repo already exists, skipping clone."
fi

if [ ! -d "ntpu-past-exam-service" ]; then
  echo "Cloning backend..."
  git clone git@github.com:NTPU-Tools/ntpu-past-exam-service.git
else
  echo "Backend repo already exists, skipping clone."
fi

echo ""

# --- Create env files if missing ---
if [ ! -f "ntpu-past-exam-service/.env" ]; then
  cp ntpu-past-exam-service/.env.example ntpu-past-exam-service/.env
  echo "Created backend .env"
else
  echo "Backend .env already exists, skipping."
fi

if [ ! -f "ntpu-past-exam/.env" ]; then
  cp ntpu-past-exam/.env.example ntpu-past-exam/.env
  echo "Created frontend .env"
else
  echo "Frontend .env already exists, skipping."
fi

echo ""

# --- Start Docker services ---
echo "Starting Docker services..."
docker compose config --quiet
docker compose up --build -d

echo ""
echo "Waiting for backend to be ready..."
backend_ready=false
for ((attempt = 1; attempt <= 60; attempt++)); do
  if curl -sf "http://localhost:${backend_port}/ping" > /dev/null 2>&1; then
    backend_ready=true
    break
  fi
  sleep 2
done

if [[ "$backend_ready" != true ]]; then
  echo "Backend did not become ready within 120 seconds." >&2
  docker compose logs --tail=100 backend >&2
  exit 1
fi
echo "Backend is ready."

echo ""

# --- Seed database ---
echo "Seeding database..."
docker compose exec -T backend python scripts/seed.py

echo ""
echo "=== Done! ==="
echo ""
echo "  Frontend:      http://localhost:${frontend_port}"
echo "  Backend API:   http://localhost:${backend_port}"
echo "  S3 Console:    http://localhost:${s3_console_port}  (minioadmin / minioadmin)"
echo ""
echo "  Login (click 帳號密碼登入 on the login page):"
echo "    admin    / admin123      (super user)"
echo "    student1 / password123   (regular user)"
echo "    student2 / password123   (regular user)"
echo ""
echo "  Logs:  docker compose logs -f"
echo "  Stop:  docker compose down"
echo "  Reset: docker compose down -v && ./bootstrap.sh"
