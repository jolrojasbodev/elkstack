#!/bin/bash

# Este script instala el Stack ELK (Elasticsearch, Logstash, Kibana) en Ubuntu Server 22.04 LTS.
# También instala Filebeat para la recolección de logs y OpenJDK 17.
# Está configurado para un entorno de PRUEBA MINIMALISTA y es COMPLETAMENTE AUTOMÁTICO.

# -- ADVERTENCIA DE SEGURIDAD --
# Este script configura Elasticsearch y Kibana para ser accesibles desde cualquier IP (0.0.0.0).
# Esto NO es seguro para entornos de producción sin configuraciones de seguridad adicionales
# como firewalls (UFW), TLS/SSL, autenticación y autorización (X-Pack Security).
# ¡AJUSTA LA CONFIGURACIÓN network.host Y server.host EN PRODUCCIÓN!
# -- FIN DE ADVERTENCIA --

# Salir inmediatamente si un comando falla
set -e

# Opcional: Descomenta la siguiente línea para depurar el script (muestra los comandos ejecutados)
# set -x

echo "Iniciando la instalación del Stack ELK en Ubuntu Server 22.04 (Modo Prueba Minimalista y Automático)..."

# --- Funciones de ayuda para esperar servicios ---

# Función para esperar a que un servicio de systemd esté activo
wait_for_service() {
    local service_name=$1
    local timeout=120
    local count=0
    echo "Esperando que el servicio $service_name esté activo..."
    while ! sudo systemctl is-active --quiet "$service_name" && [ "$count" -lt "$timeout" ]; do
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    echo "" # Nueva línea después de los puntos
    if sudo systemctl is-active --quiet "$service_name"; then
        echo "Servicio $service_name está activo."
        return 0
    else
        echo "Error: El servicio $service_name no se inició en el tiempo esperado."
        echo "Para más detalles, ejecuta: journalctl -xeu $service_name"
        return 1
    fi
}

# Función para esperar a que un puerto HTTP responda
wait_for_http_port() {
    local host=$1
    local port=$2
    local timeout=60
    local count=0
    echo "Esperando que $host:$port responda..."
    while ! curl -s "http://$host:$port" > /dev/null && [ "$count" -lt "$timeout" ]; do
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    echo "" # Nueva línea después de los puntos
    if curl -s "http://$host:$port" > /dev/null; then
        echo "$host:$port está respondiendo."
        return 0
    else
        echo "Error: $host:$port no respondió en el tiempo esperado."
        echo "Verifica que el servicio esté corriendo y el firewall no lo esté bloqueando."
        return 1
    fi
}

# --- Inicio de la instalación ---

# 1. Actualizar el sistema
echo -e "\n--- Paso 1: Actualizando el sistema ---"
sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
echo "Sistema actualizado."

# 2. Instalar OpenJDK 17 (requerido por Elasticsearch y Logstash)
echo -e "\n--- Paso 2: Instalando OpenJDK 17 ---"
sudo DEBIAN_FRONTEND=noninteractive apt install -y openjdk-17-jdk
echo "OpenJDK 17 instalado."
java -version

# 3. Importar la clave GPG de Elastic y añadir el repositorio de Elastic
echo -e "\n--- Paso 3: Añadiendo el repositorio de Elastic ---"
sudo DEBIAN_FRONTEND=noninteractive apt install -y apt-transport-https ca-certificates curl gnupg2
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-archive-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list > /dev/null
sudo DEBIAN_FRONTEND=noninteractive apt update
echo "Repositorio de Elastic añadido y apt actualizado."

# --- INSTALACIÓN DE ELASTICSEARCH ---
echo -e "\n--- Paso 4: Instalando Elasticsearch ---"
sudo DEBIAN_FRONTEND=noninteractive apt install -y elasticsearch
echo "Elasticsearch instalado."

# Configurar Elasticsearch
echo -e "\n--- Paso 5: Configurando Elasticsearch ---"
# Aumentar los límites de memoria virtual (vm.max_map_count) para Elasticsearch
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p # Aplicar cambios permanentemente

# --- MODIFICACIÓN ROBUSTA DE elasticsearch.yml ---
echo "Realizando configuración robusta de elasticsearch.yml..."
# Eliminar líneas existentes para evitar duplicados
sudo sed -i '/^network.host:/d' /etc/elasticsearch/elasticsearch.yml
sudo sed -i '/^http.port:/d' /etc/elasticsearch/elasticsearch.yml
sudo sed -i '/^discovery.seed_hosts:/d' /etc/elasticsearch/elasticsearch.yml
sudo sed -i '/^cluster.initial_master_nodes:/d' /etc/elasticsearch/elasticsearch.yml

# Añadir las configuraciones deseadas al final del archivo
sudo sh -c 'echo "network.host: 0.0.0.0" >> /etc/elasticsearch/elasticsearch.yml'
sudo sh -c 'echo "http.port: 9200" >> /etc/elasticsearch/elasticsearch.yml'
sudo sh -c 'echo "discovery.seed_hosts: [\"127.0.0.1\"]" >> /etc/elasticsearch/elasticsearch.yml'
sudo sh -c 'echo "cluster.initial_master_nodes: [\"$(hostname)\"]" >> /etc/elasticsearch/elasticsearch.yml'

# Ajustar el tamaño del heap de Java para Elasticsearch
# Para una prueba minimalista, asignamos 2GB (útil para sistemas con 4GB de RAM).
# ¡AJUSTAR ESTE VALOR SEGÚN TU RAM DISPONIBLE!
# (Generalmente el 50% de la RAM total, pero no más de 30.5GB)
HEAP_SIZE="2g" # Valor recomendado para prueba con 4GB de RAM

echo "Configurando heap de Elasticsearch a -Xms${HEAP_SIZE} -Xmx${HEAP_SIZE}..."
# Comentar líneas existentes de Xms/Xmx si las hay y añadir las nuevas al final
sudo sed -i "s/^-Xms[0-9]\+[mg MG]/#&/" /etc/elasticsearch/jvm.options
sudo sed -i "s/^-Xmx[0-9]\+[mg MG]/#&/" /etc/elasticsearch/jvm.options
sudo sh -c "echo '' >> /etc/elasticsearch/jvm.options"
sudo sh -c "echo '-Xms${HEAP_SIZE}' >> /etc/elasticsearch/jvm.options"
sudo sh -c "echo '-Xmx${HEAP_SIZE}' >> /etc/elasticsearch/jvm.options"

echo "Configuración básica de Elasticsearch aplicada. Revise /etc/elasticsearch/elasticsearch.yml para ajustes finos."

# Habilitar y iniciar Elasticsearch
echo -e "\n--- Paso 6: Habilitando y iniciando Elasticsearch ---"
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
wait_for_service elasticsearch || exit 1 # Esperar a que el servicio esté activo
wait_for_http_port localhost 9200 || exit 1 # Esperar a que el puerto HTTP responda

# --- VALIDACIÓN DE ELASTICSEARCH ---
echo -e "\n--- Verificando la instalación de Elasticsearch ---"
sudo systemctl status elasticsearch | grep "Active:"

# Resetear/Obtener la contraseña del usuario 'elastic' de forma robusta
echo "Generando/Reseteando contraseña para el usuario 'elastic'..."
ELASTIC_PASSWORD=$(sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b)
if [ -z "$ELASTIC_PASSWORD" ]; then
    echo "Error crítico: No se pudo generar la contraseña de 'elastic'. Saliendo."
    exit 1
fi
echo "La contraseña para el usuario 'elastic' es: $ELASTIC_PASSWORD"
echo "¡GUARDA esta contraseña de forma segura! La necesitarás para Kibana y cualquier cliente."

# Verificar accesibilidad y salud usando la contraseña recién obtenida
curl -X GET "localhost:9200/" -u elastic:$ELASTIC_PASSWORD --insecure
curl -X GET "localhost:9200/_cat/health?v" -u elastic:$ELASTIC_PASSWORD --insecure

# --- INSTALACIÓN DE KIBANA ---
echo -e "\n--- Paso 7: Instalando Kibana ---"
sudo DEBIAN_FRONTEND=noninteractive apt install -y kibana
echo "Kibana instalado."

# Configurar Kibana
echo -e "\n--- Paso 8: Configurando Kibana ---"
# Habilitar la conexión remota y la conexión a Elasticsearch
sudo sed -i 's/^#server.port: 5601/server.port: 5601/' /etc/kibana/kibana.yml
sudo sed -i 's/^#server.host: "localhost"/server.host: "0.0.0.0"/' /etc/kibana/kibana.yml # ACCESIBLE DESDE CUALQUIER IP
sudo sed -i 's/^#elasticsearch.hosts: \["http:\/\/localhost:9200"\]/elasticsearch.hosts: ["http:\/\/localhost:9200"]/' /etc/kibana/kibana.yml
sudo sed -i 's/^#elasticsearch.username: "kibana_system"/elasticsearch.username: "elastic"/' /etc/kibana/kibana.yml
sudo sed -i "s/^#elasticsearch.password: \"your-password\"/elasticsearch.password: \"$ELASTIC_PASSWORD\"/" /etc/kibana/kibana.yml
sudo sed -i 's/^#elasticsearch.ssl.verificationMode: full/elasticsearch.ssl.verificationMode: none/' /etc/kibana/kibana.yml # Deshabilitar SSL para facilitar pruebas, ¡NO EN PRODUCCIÓN!

echo "Configuración básica de Kibana aplicada. Revise /etc/kibana/kibana.yml para ajustes finos."

# Habilitar y iniciar Kibana
echo -e "\n--- Paso 9: Habilitando y iniciando Kibana ---"
sudo systemctl daemon-reload
sudo systemctl enable kibana
sudo systemctl start kibana
wait_for_service kibana || exit 1 # Esperar a que el servicio esté activo
wait_for_http_port localhost 5601 || exit 1 # Esperar a que el puerto HTTP responda

# --- VALIDACIÓN DE KIBANA ---
echo -e "\n--- Verificando la instalación de Kibana ---"
sudo systemctl status kibana | grep "Active:"
echo "Deberías poder acceder a Kibana en http://TU_IP_DEL_SERVIDOR:5601"

# --- INSTALACIÓN DE LOGSTASH ---
echo -e "\n--- Paso 10: Instalando Logstash ---"
sudo DEBIAN_FRONTEND=noninteractive apt install -y logstash
echo "Logstash instalado."

# Configurar Logstash (ejemplo básico: leer de beats, enviar a Elasticsearch)
echo -e "\n--- Paso 11: Configurando un pipeline básico de Logstash ---"
sudo mkdir -p /etc/logstash/conf.d
sudo bash -c 'cat << EOF > /etc/logstash/conf.d/02-beats-input.conf
input {
  beats {
    port => 5044
    ssl => false # Deshabilitar SSL para simplificar, ¡NO EN PRODUCCIÓN!
  }
}
EOF'
sudo bash -c 'cat << EOF > /etc/logstash/conf.d/30-elasticsearch-output.conf
output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "logstash-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "'"$ELASTIC_PASSWORD"'"
    ssl_enabled => false # Deshabilitar SSL para simplificar, ¡NO EN PRODUCCIÓN!
  }
}
EOF'
echo "Pipeline básico de Logstash configurado. Revise /etc/logstash/conf.d/ para ajustes finos."

# Habilitar y iniciar Logstash
echo -e "\n--- Paso 12: Habilitando y iniciando Logstash ---"
# Validar la configuración de Logstash antes de iniciar
echo "Validando configuración de Logstash..."
sudo /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t
echo "Configuración de Logstash válida."

sudo systemctl daemon-reload
sudo systemctl enable logstash
sudo systemctl start logstash
wait_for_service logstash || exit 1 # Esperar a que el servicio esté activo

# --- VALIDACIÓN DE LOGSTASH ---
echo -e "\n--- Verificando la instalación de Logstash ---"
sudo systemctl status logstash | grep "Active:"


# --- INSTALACIÓN DE FILEBEAT (Recomendado para recolectar logs) ---
echo -e "\n--- Paso 13: Instalando Filebeat ---"
sudo DEBIAN_FRONTEND=noninteractive apt install -y filebeat
echo "Filebeat instalado."

# Configurar Filebeat para enviar logs al pipeline de Logstash
echo -e "\n--- Paso 14: Configurando Filebeat ---"
# Deshabilitar salida directa a Elasticsearch y habilitar Logstash
sudo sed -i 's/^output.elasticsearch:/#output.elasticsearch:/' /etc/filebeat/filebeat.yml
sudo sed -i 's/^  hosts: \["localhost:9200"\]/#  hosts: \["localhost:9200"\]/' /etc/filebeat/filebeat.yml
sudo sed -i 's/^#output.logstash:/output.logstash:/' /etc/filebeat/filebeat.yml
sudo sed -i 's/^#  hosts: \["localhost:5044"\]/  hosts: \["localhost:5044"\]/' /etc/filebeat/filebeat.yml

# Habilitar un módulo de Filebeat (ejemplo: system logs)
sudo filebeat modules enable system
echo "Módulo 'system' de Filebeat habilitado."

# Cargar los dashboards de Kibana predefinidos por Filebeat (se conecta a Elasticsearch directamente para esto)
# Nota: Esto requiere que Kibana esté en funcionamiento y accesible.
echo "Cargando dashboards de Kibana para Filebeat..."
sudo filebeat setup --dashboards -E output.elasticsearch.username=elastic -E output.elasticsearch.password=$ELASTIC_PASSWORD -E output.elasticsearch.hosts=["localhost:9200"] -E output.elasticsearch.ssl.verification_mode=none
echo "Dashboards de Filebeat cargados."

# Cargar el índice de Filebeat en Elasticsearch
echo "Cargando índice de Filebeat en Elasticsearch..."
sudo filebeat setup --index-management -E output.elasticsearch.username=elastic -E output.elasticsearch.password=$ELASTIC_PASSWORD -E output.elasticsearch.hosts=["localhost:9200"] -E output.elasticsearch.ssl.verification_mode=none
echo "Índice de Filebeat cargado."

echo "Configuración básica de Filebeat aplicada. Revise /etc/filebeat/filebeat.yml para ajustes finos."

# Habilitar y iniciar Filebeat
echo -e "\n--- Paso 15: Habilitando y iniciando Filebeat ---"
sudo systemctl daemon-reload
sudo systemctl enable filebeat
sudo systemctl start filebeat
wait_for_service filebeat || exit 1 # Esperar a que el servicio esté activo

# --- VALIDACIÓN DE FILEBEAT ---
echo -e "\n--- Verificando la instalación de Filebeat ---"
sudo systemctl status filebeat | grep "Active:"


echo -e "\n--- Instalación del Stack ELK (y Filebeat) completada ---"

# Resumen y pasos siguientes
echo -e "\n--- Resumen y Pasos Siguientes ---"
echo "1. Elasticsearch: Escuchando en http://0.0.0.0:9200"
echo "   Usuario 'elastic' contraseña: $ELASTIC_PASSWORD"
echo "   (Guarda esta contraseña de forma segura, la necesitarás para Kibana)"
echo "2. Kibana: Accesible en http://TU_IP_DEL_SERVIDOR:5601"
echo "   (Inicia sesión con 'elastic' y la contraseña generada)"
echo "3. Logstash: Escuchando beats en el puerto 5044."
echo "4. Filebeat: Enviando logs del sistema a Logstash (y luego a Elasticsearch)."

echo -e "\n--- Pasos importantes ADICIONALES (MUY RECOMENDADOS) ---"
echo "1. Configura un **FIREWALL** (UFW) para restringir el acceso a los puertos 9200 (Elasticsearch), 5601 (Kibana) y 5044 (Logstash)."
echo "   Ejemplo para UFW (solo permite desde tu IP local):"
echo "   sudo ufw allow from TU_IP_LOCAL to any port 9200"
echo "   sudo ufw allow from TU_IP_LOCAL to any port 5601"
echo "   sudo ufw allow from TU_IP_LOCAL to any port 5044"
echo "   sudo ufw enable"
echo "2. Habilita **TLS/SSL** y la **seguridad X-Pack** (autenticación, autorización) en Elasticsearch y Kibana para producción. Esto es CRÍTICO."
echo "   Consulta la documentación oficial de Elastic: https://www.elastic.co/guide/en/elastic-stack/current/index.html"
echo "3. Ajusta los tamaños de heap de Java y otras configuraciones de rendimiento para tus necesidades específicas."
echo "4. Considera usar un servidor web (Nginx/Apache) como proxy inverso para Kibana con SSL."
echo "5. Elimina las líneas de \`ssl_enabled => false\` y \`ssl_verification_mode => none\` en las configuraciones de Logstash, Filebeat y Kibana una vez que hayas configurado SSL/TLS correctamente en Elasticsearch."

echo -e "\n¡Disfruta de tu Stack ELK de prueba!"
