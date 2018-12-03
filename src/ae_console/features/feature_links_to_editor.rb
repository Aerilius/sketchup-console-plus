module AE

  module ConsolePlugin

    class FeatureLinksToEditor

      # TODO: It would be best to test existence of filepaths on the Ruby side before rendering them as links.

      def initialize(app)
      end

      def get_javascript_path
        return 'feature_links_to_editor.js'
      end

    end # class FeatureLinksToEditor

  end # module ConsolePlugin

end # module AE
