FROM --platform=linux/amd64 node:18-alpine3.18

LABEL maintainer="https://github.com/hamzanaeemm/"
WORKDIR /app

COPY package*.json ./

# Use BuildKit secret mounting for credentials (secure alternative)
# Build: docker build --secret aws_access=${AWS_ACCESS} --secret aws_secret=${AWS_SECRET} .
# Or use environment variables at runtime instead of build time

RUN npm ci --omit=dev

COPY . .

EXPOSE 3000

CMD ["npm", "start"]