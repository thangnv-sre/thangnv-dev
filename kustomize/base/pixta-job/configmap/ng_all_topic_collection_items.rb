#"NgAllTopicCollectionItems.run"

class NgAllTopicCollectionItems < Pixta::BatchBase
  def self.run
    item_job_columns = [:item_id, :user_id, :event_name, :status, :done_at]
    halted_item_columns = [:item_id, :deleted_at, :created_at, :updated_at]

    count_item = Item.joins(:contributor).where('contributors.contributor_label_id in (?)', ContributorLabel::TOPIC_COLLECTION_LABELS).on_sale_or_exam.count
    Contributor.where(contributor_label_id: ContributorLabel::TOPIC_COLLECTION_LABELS).update_all(count_photo: 0)
    webhook = "https://hooks.slack.com/services/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"
    message = "update count photo to 0 for all"
    SlackService.new(webhook, message).call

    start = 0
    loop do
      items =Item.joins(:contributor).where('contributors.contributor_label_id in (?)', ContributorLabel::TOPIC_COLLECTION_LABELS).on_sale_or_exam.limit(10000)
      item_ids = items.map{|i| i.id}
      break if item_ids.blank?
      
      item_job_array = []
      halted_item_array = []
      done_at = Time.now
      halted_existing_ids = HaltedItem.where(item_id: item_ids).pluck(:item_id)

      items.each do |item|
        item_job_array << [item.id, item.user_id,JOB_INSTANT_NG, JOB_STATUS_SUCCESS, done_at]
        halted_item_array << [item.id, done_at, done_at, done_at] unless halted_existing_ids.include?(item.id)
      end

      message_bodys = []
      item_ids.each_slice(1000) do |item_1000|
        message_bodys << { item_id: item_1000, fields: ["status"] } 
      end

      BaseTransaction.transaction do
        ItemJob.import item_job_columns, item_job_array, validate: false
        message = "Done import records ItemJob"
        SlackService.new(webhook, message).call

        HaltedItem.import halted_item_columns, halted_item_array, validate: false
        message = "Done import records HaltedItem"
        SlackService.new(webhook, message).call

        Item.where(id: item_ids).update_all(status: CONTENT_STATUS_NG)
        message = "Done update status NG for all items"
        SlackService.new(webhook, message).call

       

        Pixta::Search::SearchIndex.new.send_message_batch(message_bodys)
        message = "Done sending mess to update search index"
        SlackService.new(webhook, message).call

        start += 10000
        message = "Done update for #{start} items, remain #{count_item - start}"
        SlackService.new(webhook, message).call
      end
    end

    item_remain =Item.joins(:contributor).where('contributors.contributor_label_id in (?)', ContributorLabel::TOPIC_COLLECTION_LABELS).on_sale_or_exam.count
    message = "Remain #{item_remain} items need to update"
    SlackService.new(webhook, message).call
  end
end