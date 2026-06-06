{ lib }:

let
  contextFrom =
    value:
    if builtins.isString value then
      value
    else if builtins.isPath value || lib.isDerivation value then
      "${value}"
    else if builtins.isList value then
      lib.concatMapStrings contextFrom value
    else if builtins.isAttrs value then
      lib.concatStrings (map contextFrom (builtins.attrValues value))
    else
      "";
in
value: lib.strings.addContextFrom (contextFrom value) (builtins.toJSON value)
