FROM python:3.12-slim
# git : demande par dbt debug et par dbt deps (paquets dbt installes depuis Git)
RUN apt-get update \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "dbt-core~=1.11.0" dbt-postgres
WORKDIR /usr/app
ENTRYPOINT ["dbt"]
