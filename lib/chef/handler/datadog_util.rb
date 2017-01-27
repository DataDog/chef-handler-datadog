# encoding: utf-8
# util class that groups common methods used by the helper classes
module DatadogUtil
  private

  def compile_error?
    @run_status.all_resources.nil? || @run_status.elapsed_time.nil? || @run_status.updated_resources.nil?
  end
end
