FROM node:18-slim

WORKDIR /app
COPY package.json .
RUN npm install --omit=dev

COPY server.js .

EXPOSE 3075
ENV LOG_DIR=/opt/admin/logs

CMD ["node", "server.js"]
