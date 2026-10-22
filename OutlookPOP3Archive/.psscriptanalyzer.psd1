@{
    Severity = @('Error')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseSingularNouns',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingPositionalParameters',
        # Required because Pester 5/6 scopes $script: per block. The step
        # journal streams map must be process-wide, or a stream opened in one
        # block is not visible to the block that closes it.
        'PSAvoidGlobalVars',
        'PSUseApprovedVerbs'
    )
}
