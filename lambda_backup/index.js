// Lambda de backup: cria um snapshot do RDS, exporta para o S3 (Parquet,
// criptografado com KMS) e, ao final, APAGA o snapshot — deixando o backup
// apenas no S3. Usa o AWS SDK v3 (ja disponivel no runtime nodejs20.x).
//
// Fluxo:
//   1. Cria um snapshot manual do RDS (CreateDBSnapshot)
//   2. Aguarda o snapshot ficar "available"
//   3. Dispara o export do snapshot para o S3 (StartExportTask)
//   4. Aguarda o export terminar (COMPLETE)
//   5. Apaga o snapshot (DeleteDBSnapshot) — o backup fica so no S3
//
// Variaveis de ambiente (injetadas pelo Terraform):
//   DB_INSTANCE_ID  - identificador da instancia RDS
//   S3_BUCKET       - bucket de destino do export
//   KMS_KEY_ARN     - chave KMS para criptografar o export
//   EXPORT_ROLE_ARN - IAM role que o servico de export assume
//   ACCOUNT_ID      - id da conta (para montar o ARN do snapshot)

const {
  RDSClient,
  CreateDBSnapshotCommand,
  StartExportTaskCommand,
  DescribeExportTasksCommand,
  DeleteDBSnapshotCommand,
  waitUntilDBSnapshotAvailable,
} = require("@aws-sdk/client-rds");

const rds = new RDSClient({});

// Aguarda o export task sair de STARTING/IN_PROGRESS ate um estado final.
async function waitForExport(exportTaskId, maxWaitMs) {
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    const out = await rds.send(
      new DescribeExportTasksCommand({ ExportTaskIdentifier: exportTaskId })
    );
    const task = out.ExportTasks && out.ExportTasks[0];
    const status = task ? task.Status : "UNKNOWN";
    console.log(`[Backup] Export ${exportTaskId} status: ${status} (${task ? task.PercentProgress : 0}%)`);

    if (status === "COMPLETE") return "COMPLETE";
    if (status === "FAILED" || status === "CANCELED") {
      throw new Error(`Export terminou com status ${status}: ${task && task.FailureCause ? task.FailureCause : ""}`);
    }
    // espera 20s antes de checar de novo
    await new Promise((r) => setTimeout(r, 20000));
  }
  throw new Error("Tempo esgotado aguardando o export completar.");
}

exports.handler = async function (event) {
  const dbInstanceId = process.env.DB_INSTANCE_ID;
  const bucket = process.env.S3_BUCKET;
  const kmsKeyArn = process.env.KMS_KEY_ARN;
  const exportRoleArn = process.env.EXPORT_ROLE_ARN;
  const region = process.env.AWS_REGION;
  const accountId = process.env.ACCOUNT_ID;

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const snapshotId = `cosmos-snap-${stamp}`;
  const exportTaskId = `cosmos-export-${stamp}`;

  try {
    console.log(`[Backup] Criando snapshot ${snapshotId} do RDS ${dbInstanceId}...`);
    await rds.send(
      new CreateDBSnapshotCommand({
        DBInstanceIdentifier: dbInstanceId,
        DBSnapshotIdentifier: snapshotId,
      })
    );

    console.log("[Backup] Aguardando o snapshot ficar disponivel...");
    await waitUntilDBSnapshotAvailable(
      { client: rds, maxWaitTime: 600 },
      { DBSnapshotIdentifier: snapshotId }
    );

    const snapshotArn = `arn:aws:rds:${region}:${accountId}:snapshot:${snapshotId}`;

    console.log(`[Backup] Iniciando export ${exportTaskId} para s3://${bucket}...`);
    await rds.send(
      new StartExportTaskCommand({
        ExportTaskIdentifier: exportTaskId,
        SourceArn: snapshotArn,
        S3BucketName: bucket,
        S3Prefix: "rds-exports",
        IamRoleArn: exportRoleArn,
        KmsKeyId: kmsKeyArn,
      })
    );

    console.log("[Backup] Export iniciado. Aguardando conclusao...");
    await waitForExport(exportTaskId, 13 * 60 * 1000); // ate 13 min

    console.log(`[Backup] Export concluido. Apagando o snapshot ${snapshotId}...`);
    await rds.send(new DeleteDBSnapshotCommand({ DBSnapshotIdentifier: snapshotId }));

    console.log("[Backup] Snapshot apagado. Backup finalizado (apenas no S3).");
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Backup concluido com sucesso. Snapshot apagado, dados apenas no S3.",
        exportTask: exportTaskId,
        destino: `s3://${bucket}/rds-exports/${exportTaskId}`,
      }),
    };
  } catch (error) {
    console.error("[Backup] Erro:", error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message, snapshot: snapshotId, exportTask: exportTaskId }),
    };
  }
};
