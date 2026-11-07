# frozen_string_literal: true

# Global holds the one thing upstream's gcal-global.c exists for: a record
# of the application's main thread, taken once at startup, so that code
# which must only run there can assert that it does.
#
# Upstream takes this record in a constructor function that runs before
# main() through GLib's G_DEFINE_CONSTRUCTOR. This file's body runs once,
# the first time anything requires it, which — Ruby GTK apps being
# single-threaded — is always that same main thread, so the moment serves
# the same purpose.
#
# Ported from upstream's src/core/gcal-global.c and src/core/gcal-global.h.
#
module Global
  @main_thread = Thread.current

  module_function

  # Upstream's gcal_get_main_thread().
  def main_thread = @main_thread

  # Upstream's GCAL_IS_MAIN_THREAD() macro.
  def main_thread? = Thread.current.equal?(@main_thread)
end
