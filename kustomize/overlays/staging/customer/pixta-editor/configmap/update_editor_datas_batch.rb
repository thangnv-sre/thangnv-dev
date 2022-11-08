# ruby script/rails runner "UpdateEditorData.run" -e staging
class UpdateEditorDatasBatch < Pixta::BatchBase
  def self.run
    process
  end
  private
  def self.process
    #update redirect uri of oauth application for login on staging
    Rails.logger.info("Update Oauth Application")
    da = Doorkeeper::Application.find 7
    da.update!(redirect_uri: "https://staging.pixtastock.com/editor/auth/callback https://staging.pixta.jp/editor/auth/callback")
    #update origin of api consumer for download image on staging
    Rails.logger.info("Update ApiConsumer")
    api = ApiConsumer.find 55
    api.update!(origin: "https://staging.pixtastock.com")
    Rails.logger.info("Update ApiConsumer")
    api = ApiConsumer.find 54
    api.update!(origin: "https://staging.pixta.jp")
    Rails.logger.info("Update ApiConsumer")
    api = ApiConsumer.find 53
    api.update!(origin: "https://editor-dev.pixtastock.com")
  end
end