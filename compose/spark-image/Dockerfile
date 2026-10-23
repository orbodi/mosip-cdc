FROM apache/spark:4.0.2-python3
USER root
# httpx : appels à l'API de pré-inscription
RUN pip3 install --no-cache-dir --break-system-packages httpx==0.28.1 2>/dev/null \
 || pip3 install --no-cache-dir httpx==0.28.1
COPY spark-defaults.conf /opt/spark/conf/spark-defaults.conf
USER spark
