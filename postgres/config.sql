CREATE ROLE view_api WITH LOGIN;
CREATE DATABASE iguidedb;
GRANT ALL PRIVILEGES ON DATABASE iguidedb TO view_api;
