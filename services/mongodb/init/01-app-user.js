// Creates the least-privileged user the backend authenticates with, so the
// application never holds the root credentials. Mirrors what will live in SSM.
//
// Runs once, only when /data/db is empty. To re-run: docker compose down -v.

const db_name = process.env.MONGO_INITDB_DATABASE;
const username = process.env.MONGO_APP_USERNAME;
const password = process.env.MONGO_APP_PASSWORD;

if (!db_name || !username || !password) {
  throw new Error(
    "MONGO_INITDB_DATABASE, MONGO_APP_USERNAME and MONGO_APP_PASSWORD must be set"
  );
}

const appDb = db.getSiblingDB(db_name);

appDb.createUser({
  user: username,
  pwd: password,
  // readWrite on this database only - no access to admin or other databases.
  roles: [{ role: "readWrite", db: db_name }],
});

// Touch the collection so it exists before the first insert. No secondary index:
// every query the API issues is either an _id lookup or a sort on _id, and the
// default _id index already serves both.
appDb.createCollection("items");

print(`Created user '${username}' with readWrite on '${db_name}'.`);
