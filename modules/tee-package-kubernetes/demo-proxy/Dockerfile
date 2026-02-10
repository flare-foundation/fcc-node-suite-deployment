# Use lightweight Python image
FROM python:3.11-slim

# Install Flask
RUN pip install flask

# Copy app
COPY app.py /app/app.py

WORKDIR /app

# Run the Python app
CMD ["python", "app.py"]