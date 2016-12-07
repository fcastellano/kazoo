# Rates

Manage ratedeck DB.
Category - "rates".
Only superadmin can use this module.

## Fields

CSV files for all actions use the same list of fields. Names of fields match the names of keys in the CouchDB [rate document](../../crossbar/doc/rates.md#schema).

**Note**: `routes` and `options` fields can not be defined via CSV file (because their values are lists).
`routes` is automatically generated from the `prefix`. For example: `prefix` 380 results in `"routes":["^\\+?380.+$"]`.

## Actions

### Import

Import rates from CSV.
`prefix` and `rate_cost` are mandatory fields.

### Export

Export all rates into CSV.
No input file.

### Delete

Delete rates for prefixes in CSV file.
`prefix` is a mandatory field.
The rate will be deleted only if all defined fields in CSV file match the appropriate keys in rate document. An undefined field in CSV file means "match any".
