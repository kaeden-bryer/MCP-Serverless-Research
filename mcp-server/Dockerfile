# Lambda Web Adapter lets this same image run on both EC2 and AWS Lambda.
# On EC2, the adapter binary is simply never invoked.
# On Lambda, it translates Lambda invocation events into HTTP requests.
FROM public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 AS lambda-adapter

FROM python:3.12-slim

COPY --from=lambda-adapter /lambda-adapter /opt/extensions/lambda-adapter

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

# PORT tells the Lambda Web Adapter where to forward requests.
# Host/port for FastMCP are set in server.py directly.
ENV PORT=8080

EXPOSE 8080

CMD ["python", "server.py"]
