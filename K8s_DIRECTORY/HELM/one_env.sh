#!/bin/bash
set -e

APP_NAME="demo-app"
RELEASE_NAME="myapp"
NODEPORT="30080"

echo "==============================="
echo "STEP 1: Create Helm Chart"
echo "==============================="

helm create $APP_NAME
cd $APP_NAME

echo "==============================="
echo "STEP 2: Clean Default Templates"
echo "==============================="

rm -rf templates/*
mkdir -p templates

echo "==============================="
echo "STEP 3: Create values.yaml"
echo "==============================="

cat <<EOF > values.yaml
replicaCount: 2

image:
  repository: nginx
  tag: "1.25"
  pullPolicy: IfNotPresent

service:
  type: NodePort
  port: 80
  nodePort: ${NODEPORT}

app:
  message: "Hello from HELM v1"
EOF

echo "==============================="
echo "STEP 3a: Create Deployment Template"
echo "==============================="

cat <<EOF > templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 80
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "{{ .Values.app.message }}" > /usr/share/nginx/html/index.html;
              nginx -g 'daemon off;'
EOF

echo "==============================="
echo "STEP 3b: Create Service Template"
echo "==============================="

cat <<EOF > templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ .Release.Name }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 80
      nodePort: {{ .Values.service.nodePort }}
EOF

echo "==============================="
echo "STEP 4: Helm Chart Ready"
echo "==============================="

echo "Run manually:"
echo "  helm install ${RELEASE_NAME} ."
echo "  kubectl get pods"
echo "  kubectl get svc"
echo "Access app using NodeIP:${NODEPORT}"

