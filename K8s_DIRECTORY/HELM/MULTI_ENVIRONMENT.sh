#!/bin/bash
set -e

APP_NAME="env-app"

echo "==============================="
echo "Creating Helm Chart Skeleton"
echo "==============================="

helm create $APP_NAME
cd $APP_NAME

echo "==============================="
echo "Cleaning default templates"
echo "==============================="

rm -rf templates/*
mkdir -p templates

echo "==============================="
echo "Creating base values.yaml"
echo "==============================="

cat <<EOF > values.yaml
replicaCount: 1

image:
  repository: nginx
  tag: "1.25"

service:
  type: NodePort
  port: 80
  nodePort: 30084

env:
  name: "DEFAULT"
EOF

echo "==============================="
echo "Creating environment-specific values"
echo "==============================="

cat <<EOF > values-dev.yaml
service:
  nodePort: 30090

env:
  name: "DEV"
EOF

cat <<EOF > values-qa.yaml
service:
  nodePort: 30091

env:
  name: "QA"
EOF

cat <<EOF > values-prod.yaml
service:
  nodePort: 30092

env:
  name: "PROD"
EOF

echo "==============================="
echo "Creating Deployment template"
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
              echo "HELLO! You hit POD of {{ .Values.env.name }} environment" \
              > /usr/share/nginx/html/index.html;
              nginx -g 'daemon off;'
EOF

echo "==============================="
echo "Creating Service template"
echo "==============================="

cat <<EOF > templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
spec:
  type: NodePort
  selector:
    app: {{ .Release.Name }}
  ports:
    - port: 80
      targetPort: 80
      nodePort: {{ .Values.service.nodePort }}
EOF

echo "==============================="
echo "FILES CREATED SUCCESSFULLY"
echo "==============================="

echo "Next (manual commands):"
echo "  kubectl create ns dev"
echo "  kubectl create ns qa"
echo "  kubectl create ns prod"
echo ""
echo "  helm install dev-app . -n dev -f values-dev.yaml"
echo "  helm install qa-app . -n qa -f values-qa.yaml"
echo "  helm install prod-app . -n prod -f values-prod.yaml"

