FROM python:3.12-slim
RUN pip install --no-cache-dir "dbt-core~=1.11.0" dbt-postgres
WORKDIR /usr/app
ENTRYPOINT ["dbt"]
