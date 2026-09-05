# Stock MongoDB from Docker Hub plus one init script.
# Pinned to a minor version so a rebuild cannot silently jump major releases.
FROM mongo:8.0

# Scripts in this directory are executed by the entrypoint exactly once, on the
# first start of an empty data volume (mongo-data). They run as the root user
# created from MONGO_INITDB_ROOT_USERNAME/PASSWORD.
COPY init/ /docker-entrypoint-initdb.d/

EXPOSE 27017
