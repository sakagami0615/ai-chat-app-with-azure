FROM python:3.14-slim@sha256:c3e521df8b2b498a7a682e7e18676771cb80c6b75b8699af886b2d554ce40151

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8501

CMD ["streamlit", "run", "app/streamlit_app.py", "--server.headless=true", "--server.address=0.0.0.0", "--server.port=8501"]
