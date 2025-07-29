FROM python:3.11-slim

WORKDIR /app

# Install required Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Run the simulator
CMD ["python", "sensor_simulator.py"]