-- Floor plan drawings and seal markers (task 5.3)
CREATE TABLE "floor_drawings" (
    "id" TEXT NOT NULL,
    "floor_id" TEXT NOT NULL,
    "file_path" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "width" INTEGER NOT NULL,
    "height" INTEGER NOT NULL,
    "file_size" INTEGER NOT NULL,
    "uploaded_by_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "floor_drawings_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "floor_drawings_floor_id_key" ON "floor_drawings"("floor_id");

ALTER TABLE "floor_drawings" ADD CONSTRAINT "floor_drawings_floor_id_fkey" FOREIGN KEY ("floor_id") REFERENCES "job_floors"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "floor_drawings" ADD CONSTRAINT "floor_drawings_uploaded_by_id_fkey" FOREIGN KEY ("uploaded_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "seal_markers" (
    "id" TEXT NOT NULL,
    "seal_id" TEXT NOT NULL,
    "floor_id" TEXT NOT NULL,
    "x" DOUBLE PRECISION NOT NULL,
    "y" DOUBLE PRECISION NOT NULL,
    "created_by_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "seal_markers_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "seal_markers_seal_id_key" ON "seal_markers"("seal_id");
CREATE INDEX "seal_markers_floor_id_idx" ON "seal_markers"("floor_id");
CREATE INDEX "seal_markers_updated_at_idx" ON "seal_markers"("updated_at");

ALTER TABLE "seal_markers" ADD CONSTRAINT "seal_markers_seal_id_fkey" FOREIGN KEY ("seal_id") REFERENCES "seals"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "seal_markers" ADD CONSTRAINT "seal_markers_floor_id_fkey" FOREIGN KEY ("floor_id") REFERENCES "job_floors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "seal_markers" ADD CONSTRAINT "seal_markers_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
