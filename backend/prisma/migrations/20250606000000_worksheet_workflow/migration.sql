-- CreateEnum
CREATE TYPE "WorkSheetStatus" AS ENUM ('draft', 'submitted', 'reviewed', 'ready_for_invoice', 'invoiced');

-- AlterTable
ALTER TABLE "change_log" ADD COLUMN "metadata" JSONB;

-- CreateTable
CREATE TABLE "worksheets" (
    "id" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "status" "WorkSheetStatus" NOT NULL DEFAULT 'draft',
    "period_from" TIMESTAMP(3),
    "period_to" TIMESTAMP(3),
    "note" TEXT,
    "internal_note" TEXT,
    "created_by_id" TEXT NOT NULL,
    "submitted_at" TIMESTAMP(3),
    "reviewed_at" TIMESTAMP(3),
    "ready_for_invoice_at" TIMESTAMP(3),
    "invoiced_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "worksheets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "worksheet_workers" (
    "id" TEXT NOT NULL,
    "worksheet_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "worksheet_workers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "worksheet_items" (
    "id" TEXT NOT NULL,
    "worksheet_id" TEXT NOT NULL,
    "seal_id" TEXT NOT NULL,
    "seal_entry_id" TEXT NOT NULL,
    "floor_id" TEXT NOT NULL,
    "worker_id" TEXT NOT NULL,
    "seal_number" TEXT NOT NULL,
    "entry_type" TEXT NOT NULL,
    "dimension" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "unit_price" DECIMAL(10,2),
    "total_price" DECIMAL(10,2),
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "worksheet_items_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "worksheets_job_id_idx" ON "worksheets"("job_id");

-- CreateIndex
CREATE INDEX "worksheets_status_idx" ON "worksheets"("status");

-- CreateIndex
CREATE UNIQUE INDEX "worksheet_workers_worksheet_id_user_id_key" ON "worksheet_workers"("worksheet_id", "user_id");

-- CreateIndex
CREATE INDEX "worksheet_items_worksheet_id_idx" ON "worksheet_items"("worksheet_id");

-- CreateIndex
CREATE UNIQUE INDEX "worksheet_items_worksheet_id_seal_entry_id_key" ON "worksheet_items"("worksheet_id", "seal_entry_id");

-- AddForeignKey
ALTER TABLE "worksheets" ADD CONSTRAINT "worksheets_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "jobs"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "worksheets" ADD CONSTRAINT "worksheets_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "worksheet_workers" ADD CONSTRAINT "worksheet_workers_worksheet_id_fkey" FOREIGN KEY ("worksheet_id") REFERENCES "worksheets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "worksheet_workers" ADD CONSTRAINT "worksheet_workers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "worksheet_items" ADD CONSTRAINT "worksheet_items_worksheet_id_fkey" FOREIGN KEY ("worksheet_id") REFERENCES "worksheets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "worksheet_items" ADD CONSTRAINT "worksheet_items_seal_id_fkey" FOREIGN KEY ("seal_id") REFERENCES "seals"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "worksheet_items" ADD CONSTRAINT "worksheet_items_seal_entry_id_fkey" FOREIGN KEY ("seal_entry_id") REFERENCES "seal_entries"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
