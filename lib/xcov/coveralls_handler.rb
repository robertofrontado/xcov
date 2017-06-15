require "tempfile"

module Xcov
  class CoverallsHandler

    class << self

      def submit(report)
        coveralls_json_path = convert_and_store_coveralls_json(report)
        perform_request(coveralls_json_path)
      end

      private

      def convert_and_store_coveralls_json(report)
        root_path = `git rev-parse --show-toplevel`
        root_path.delete!("\n")
        root_path << '/'

        # Iterate through targets
        source_files = []
        report.targets.each do |target|
          # Iterate through target files
          target.files.each do |file|
            next if file.ignored

            # Iterate through file lines
            lines = []
            file.lines.each do |line|
              lines << line.execution_count if line.executable
              lines << nil unless line.executable
            end

            relative_path = file.location
            relative_path.slice!(root_path)
            source_files << {
              name: relative_path,
              source_digest: digest_for_file(relative_path),
              coverage: lines
            }
          end
        end

        git_info = {
            :head => {
              :id => ENV.fetch("GIT_ID", `git log -1 --pretty=format:'%H'`),
              :author_name => ENV.fetch("GIT_AUTHOR_NAME", `git log -1 --pretty=format:'%aN'`),
              :author_email => ENV.fetch("GIT_AUTHOR_EMAIL", `git log -1 --pretty=format:'%ae'`),
              :committer_name => ENV.fetch("GIT_COMMITTER_NAME", `git log -1 --pretty=format:'%cN'`),
              :committer_email => ENV.fetch("GIT_COMMITTER_EMAIL", `git log -1 --pretty=format:'%ce'`),
              :message => ENV.fetch("GIT_MESSAGE", `git log -1 --pretty=format:'%s'`)
              },
            :branch => ENV.fetch("GIT_BRANCH", `git rev-parse --abbrev-ref HEAD`)
            }

        json = {
          service_job_id: Xcov.config[:coveralls_service_job_id],
          service_name: Xcov.config[:coveralls_service_name],
          repo_token: Xcov.config[:coveralls_repo_token],
          git: git_info,
          source_files: source_files
        }

        require "json"

        # Persist
        coveralls_json_file = Tempfile.new("coveralls_report.json")
        File.open(coveralls_json_file.path, "wb") do |file|
          file.puts JSON.pretty_generate(json)
          file.close
        end

        # Return path
        return coveralls_json_file.path
      end

      def perform_request(coveralls_json_path)
        require 'net/http/post/multipart'

        # Build request
        url = URI.parse("https://coveralls.io/api/v1/jobs")
        UI.message "Uploading coverage report to coveralls.io".yellow
        request = Net::HTTP::Post::Multipart.new(
          url.path,
          "json_file" => UploadIO.new(File.new(coveralls_json_path), "text/plain", "coveralls_report.json")
        )

        # Perform request
        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        response = http.request(request)

        if response.code == "200"
          UI.message "Submitted report to coveralls.io successfully".green
        else
          UI.message "There was an error submitting the report to coveralls.io".red
          UI.message response.body.red
        end
      end

      def digest_for_file(file_path)
        hash = `git hash-object #{file_path}`
        hash.delete!("\n")
        return hash
      end

    end

  end
end
