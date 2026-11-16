# Solid Queue 1.7's additive batch schema. Existing jobs and executions are retained.
class AddSolidQueueBatches < ActiveRecord::Migration[8.1]
  def down
    raise ActiveRecord::IrreversibleMigration, "Retain batch/job state; use compatible code rollback"
  end

  def change
    add_column :solid_queue_jobs, :batch_id, :bigint
    add_index :solid_queue_jobs, :batch_id

    create_table :solid_queue_batches do |t|
      t.string :active_job_batch_id
      t.string :description
      t.text :on_finish
      t.text :on_success
      t.text :on_failure
      t.text :metadata
      t.integer :total_jobs, default: 0, null: false
      t.integer :completed_jobs, default: 0, null: false
      t.integer :failed_jobs, default: 0, null: false
      t.datetime :enqueued_at
      t.datetime :finished_at
      t.datetime :failed_at
      t.timestamps
      t.index :active_job_batch_id, unique: true
      t.index :finished_at
    end

    create_table :solid_queue_batch_executions do |t|
      t.references :job, null: false, index: { unique: true }, foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.references :batch, null: false, foreign_key: { to_table: :solid_queue_batches, on_delete: :cascade }
      t.datetime :created_at, null: false
    end
  end
end
