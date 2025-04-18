#! @shell@

source @out@/nix-support/utils.bash

expandResponseParams "$@"

output="a.out"
should_add_repro=true
for arg in "${params[@]}"; do
  case "$arg" in
    -r|--version)
      should_add_repro=false
      ;;
    *)
      ;;
  esac
  case "$prev" in
    -o)
      output="$arg"
      ;;
    *)
      ;;
  esac
  prev="$arg"
done

export LLD_REPRODUCE="$output.repro.tar"
if @targetPrefix@nix-wrap-lld "$@"; then
  if $should_add_repro; then
    gzip "$LLD_REPRODUCE"
    @targetPrefix@objcopy --add-section ".lld_repro=$LLD_REPRODUCE.gz" "$output"
    rm -f "$LLD_REPRODUCE.gz"
  fi
  exitcode=0
else
  # Some Nix packages don't link with lld so just use bfd instead.
  @targetPrefix@ld.bfd "$@"
  exitcode=$?
fi

rm -f "$LLD_REPRODUCE"
exit $exitcode
