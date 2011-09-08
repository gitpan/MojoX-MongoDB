#!/usr/bin/perl

use Test::More;

BEGIN {
    plan skip_all => "Spelling tests only for authors"
        unless -e '.author'
}

use Test::Spelling;
set_spell_cmd('aspell list -l en');
add_stopwords(<DATA>);
all_pod_files_spelling_ok('lib');

__END__
Autoincrementing
BSON
DateTime
GEOSPATIAL
GitHub
Github
GridFS
IRC
JSON
MONGO
MONGODB
MapReduce
MaxKey
MinKey
Mojolicious
Mongo
MongoDB
MongoDB's
Multi
Multithreading
OID
OOP
ObjectId
SQL
TCP
Tailable
Timestamp
Timestamps
UTF
Username
ack
bigint
cleartext
deserialization
deserialize
deserialized
fs
fsync
geospatial
ixhash
md
metadata
minimalist
minimalistic
mongo
mongod
multi
namespace
ns
pageview
pre
requery
sharding
snapshotted
storable
tailable
taronishino
timestamp
timestamps
unintuitively
unordered
upsert
upserts
username
utf
Incrementing
bys
wtimeout
API
datetime
mongos
