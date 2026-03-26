# Use an official slim Python base
FROM python:3.11-slim

# Keep Python output unbuffered and avoid .pyc files
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install minimal build tools for wheels, then clean apt cache
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential gcc && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements file and install dependencies (including gunicorn)
COPY requirements.txt .
RUN pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir gunicorn && \
    pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY globomantics-asset-bundle /app/globomantics-asset-bundle
COPY app.py /app

# Create a non-root user and give ownership of the app directory
RUN groupadd -r app && useradd -r -g app -d /app -s /usr/sbin/nologin app && \
    chown -R app:app /app

USER app

EXPOSE 8080

# Run the Flask app via gunicorn (module: object)
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app", "--workers", "2", "--threads", "4", "--worker-class", "gthread"]