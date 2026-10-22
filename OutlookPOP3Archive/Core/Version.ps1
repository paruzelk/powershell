# Single source of truth for product and schema versions.
# Every module reads from here; nothing else hardcodes a version string.

$script:OPAApplicationVersion             = '0.9.4-rc1-build2.6.2-PREVIEW1'
$script:OPATransactionSchemaVersion       = '2.5.4'
$script:OPATransactionSchemaSupported     = @('2.5.1', '2.5.2', '2.5.3', '2.5.4')
$script:OPADuplicateIndexSchemaVersion    = '1.2'
$script:OPADuplicateIndexSchemasSupported = @('1.0', '1.1', '1.2')
