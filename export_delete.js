const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");
const ExcelJS = require("exceljs");

const OUTPUT_DIR = path.join(__dirname, "..", "log history order");

// ============================================================
// 1. INIT FIREBASE ADMIN
// ============================================================
const serviceAccount = require(path.join(OUTPUT_DIR, "serviceAccountKey.json"));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// ============================================================
// HELPERS
// ============================================================
function fmtItems(data) {
  const items = data.items;
  if (Array.isArray(items) && items.length > 0) {
    return items
      .map((item) => {
        const name = (item.name ?? "").trim();
        const qty = item.qty ?? 1;
        return name ? (qty > 1 ? `${name} x${qty}` : name) : "";
      })
      .filter(Boolean)
      .join(", ");
  }
  return data.grocery ?? "-";
}

function fmtDate(ts) {
  if (!ts) return "-";
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return d.toLocaleDateString("ms-MY", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function shortDate(ts) {
  if (!ts) return "-";
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return d.toLocaleDateString("ms-MY", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
}

// ============================================================
// STYLING CONSTANTS
// ============================================================
const TEAL = "FF0D7377";
const TEAL_LIGHT = "FF14C38E";
const WHITE = "FFFFFFFF";
const HEADER_FONT = { name: "Calibri", bold: true, color: { argb: WHITE }, size: 11 };
const CELL_FONT = { name: "Calibri", size: 10 };
const BORDER = {
  top: { style: "thin", color: { argb: "FFCCCCCC" } },
  left: { style: "thin", color: { argb: "FFCCCCCC" } },
  bottom: { style: "thin", color: { argb: "FFCCCCCC" } },
  right: { style: "thin", color: { argb: "FFCCCCCC" } },
};

// ============================================================
// 2. MAIN
// ============================================================
async function main() {
  console.log("📦 Fetching delivered orders...");

  const snapshot = await db
    .collection("orders")
    .where("status", "==", "delivered")
    .get();

  if (snapshot.empty) {
    console.log("✅ No delivered orders to process.");
    return;
  }

  console.log(`Found ${snapshot.size} delivered orders.`);

  // --- Aggregate data ---
  const monthlyMap = {};
  const dailyMap = {};
  const riderMap = {};
  const orderRows = [];

  for (const doc of snapshot.docs) {
    const data = { id: doc.id, ...doc.data() };
    const deliveredAt = data.delivered_at?.toDate?.() ?? new Date();
    const createdAt = data.created_at?.toDate?.() ?? null;
    const monthKey = `${deliveredAt.getFullYear()}-${String(deliveredAt.getMonth() + 1).padStart(2, "0")}`;
    const dayKey = `${deliveredAt.getFullYear()}-${String(deliveredAt.getMonth() + 1).padStart(2, "0")}-${String(deliveredAt.getDate()).padStart(2, "0")}`;
    const fare = parseFloat(data.fare ?? data.total ?? 0);
    const distance = parseFloat(data.distance_km ?? 0);
    const riderUid = data.rider_uid ?? "unknown";
    const riderName = data.rider_name ?? "N/A";

    // Monthly aggregate
    if (!monthlyMap[monthKey]) monthlyMap[monthKey] = { totalFare: 0, totalOrders: 0, totalDistance: 0 };
    monthlyMap[monthKey].totalFare += fare;
    monthlyMap[monthKey].totalOrders += 1;
    monthlyMap[monthKey].totalDistance += distance;

    // Daily aggregate
    if (!dailyMap[dayKey]) dailyMap[dayKey] = { totalFare: 0, totalOrders: 0 };
    dailyMap[dayKey].totalFare += fare;
    dailyMap[dayKey].totalOrders += 1;

    // Rider aggregate
    if (!riderMap[riderUid]) riderMap[riderUid] = { name: riderName, totalFare: 0, totalOrders: 0 };
    riderMap[riderUid].totalFare += fare;
    riderMap[riderUid].totalOrders += 1;

    // Order detail row
    const statusLabels = {
      pending: "Menunggu",
      accepted: "Diterima",
      "on the way": "Dalam Perjalanan",
      delivered: "Selesai",
    };

    orderRows.push([
      data.id ?? "-",
      fmtDate(createdAt),
      fmtDate(deliveredAt),
      statusLabels[data.status] ?? data.status,
      data.user_email ?? "-",
      data.whatsapp ?? "-",
      fmtItems(data),
      data.shop_name ?? "-",
      data.details ?? "-",
      data.drop ?? "-",
      distance.toFixed(2),
      `RM ${fare.toFixed(2)}`,
      riderName,
      `${data.shop_lat ?? ""}, ${data.shop_lng ?? ""}`,
      `${data.drop_lat ?? ""}, ${data.drop_lng ?? ""}`,
    ]);
  }

  // --- Save aggregate to Firestore ---
  for (const [monthKey, agg] of Object.entries(monthlyMap)) {
    const docRef = db.collection("revenue").doc("monthly").collection(monthKey).doc("summary");
    const existingSnap = await docRef.get();
    const existing = existingSnap.data() ?? {};

    const updated = {
      totalFare: (existing.totalFare ?? 0) + agg.totalFare,
      totalOrders: (existing.totalOrders ?? 0) + agg.totalOrders,
      totalDistance: (existing.totalDistance ?? 0) + agg.totalDistance,
    };

    const daily = { ...(existing.daily ?? {}) };
    for (const [dayKey, dayAgg] of Object.entries(dailyMap)) {
      if (dayKey.startsWith(monthKey)) {
        if (!daily[dayKey]) daily[dayKey] = { totalFare: 0, totalOrders: 0 };
        daily[dayKey].totalFare = (daily[dayKey].totalFare ?? 0) + dayAgg.totalFare;
        daily[dayKey].totalOrders = (daily[dayKey].totalOrders ?? 0) + dayAgg.totalOrders;
      }
    }
    updated.daily = daily;

    const riders = { ...(existing.riders ?? {}) };
    for (const [riderUid, riderAgg] of Object.entries(riderMap)) {
      if (!riders[riderUid]) riders[riderUid] = { name: riderAgg.name, totalFare: 0, totalOrders: 0 };
      riders[riderUid].totalFare = (riders[riderUid].totalFare ?? 0) + riderAgg.totalFare;
      riders[riderUid].totalOrders = (riders[riderUid].totalOrders ?? 0) + riderAgg.totalOrders;
    }
    updated.riders = riders;

    await docRef.set(updated, { merge: true });
    console.log(`✅ Aggregate saved for ${monthKey}`);
  }

  // --- Generate Excel ---
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  const now = new Date();
  const dateStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}_${String(now.getHours()).padStart(2, "0")}${String(now.getMinutes()).padStart(2, "0")}`;
  const filePath = path.join(OUTPUT_DIR, `orders_${dateStr}.xlsx`);

  const workbook = new ExcelJS.Workbook();
  workbook.creator = "BunnyFresh Export";
  workbook.created = new Date();

  // ============ SHEET 1: Semua Pesanan ============
  const ws1 = workbook.addWorksheet("Semua Pesanan", {
    views: [{ state: "frozen", ySplit: 1 }],
  });

  const headers1 = [
    "ID Pesanan",
    "Dicipta",
    "Siap",
    "Status",
    "Pelanggan (Email)",
    "WhatsApp",
    "Barang",
    "Kedai",
    "Butiran",
    "Alamat Hantar",
    "Jarak (km)",
    "Pendapatan (RM)",
    "Rider",
    "Koordinat Kedai",
    "Koordinat Hantar",
  ];

  const headerRow1 = ws1.addRow(headers1);
  headerRow1.eachCell((cell) => {
    cell.font = HEADER_FONT;
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: TEAL } };
    cell.alignment = { vertical: "middle", horizontal: "center", wrapText: true };
    cell.border = BORDER;
  });
  headerRow1.height = 36;

  // Data rows with alternating colors
  for (let i = 0; i < orderRows.length; i++) {
    const row = ws1.addRow(orderRows[i]);
    const bgColor = i % 2 === 0 ? "FFF5F5F5" : "FFFFFFFF";
    row.eachCell((cell) => {
      cell.font = CELL_FONT;
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: bgColor } };
      cell.alignment = { vertical: "middle", wrapText: true };
      cell.border = BORDER;
    });
  }

  // Column widths
  ws1.getColumn(1).width = 22;  // ID
  ws1.getColumn(2).width = 18;  // Dicipta
  ws1.getColumn(3).width = 18;  // Siap
  ws1.getColumn(4).width = 12;  // Status
  ws1.getColumn(5).width = 28;  // Email
  ws1.getColumn(6).width = 16;  // WhatsApp
  ws1.getColumn(7).width = 36;  // Barang
  ws1.getColumn(8).width = 22;  // Kedai
  ws1.getColumn(9).width = 28;  // Butiran
  ws1.getColumn(10).width = 28; // Alamat
  ws1.getColumn(11).width = 12; // Jarak
  ws1.getColumn(12).width = 16; // Pendapatan
  ws1.getColumn(13).width = 18; // Rider
  ws1.getColumn(14).width = 22; // Koordinat Kedai
  ws1.getColumn(15).width = 22; // Koordinat Hantar

  // Auto-filter
  ws1.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: orderRows.length + 1, column: headers1.length },
  };

  // ============ SHEET 2: Ringkasan ============
  const ws2 = workbook.addWorksheet("Ringkasan");

  // --- Monthly summary ---
  ws2.addRow(["RINGKASAN BULANAN"]).eachCell((cell) => {
    cell.font = { name: "Calibri", bold: true, size: 14, color: { argb: WHITE } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: TEAL } };
    cell.alignment = { vertical: "middle", horizontal: "center" };
  });
  ws2.mergeCells("A1:D1");
  ws2.getRow(1).height = 32;

  const monthHeader = ws2.addRow(["Bulan", "Pesanan", "Jarak (km)", "Pendapatan (RM)"]);
  monthHeader.eachCell((cell) => {
    cell.font = HEADER_FONT;
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: TEAL_LIGHT } };
    cell.alignment = { vertical: "middle", horizontal: "center" };
    cell.border = BORDER;
  });

  for (const [monthKey, agg] of Object.entries(monthlyMap).sort()) {
    const row = ws2.addRow([monthKey, agg.totalOrders, agg.totalDistance.toFixed(2), `RM ${agg.totalFare.toFixed(2)}`]);
    row.eachCell((cell) => {
      cell.font = CELL_FONT;
      cell.alignment = { vertical: "middle", horizontal: "center" };
      cell.border = BORDER;
    });
  }

  // --- Daily summary (compact) ---
  ws2.addRow([]);
  ws2.addRow(["RINGKASAN HARIAN"]).eachCell((cell) => {
    cell.font = { name: "Calibri", bold: true, size: 14, color: { argb: WHITE } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: TEAL } };
    cell.alignment = { vertical: "middle", horizontal: "center" };
  });
  ws2.mergeCells(`A${ws2.lastRow.number}:D${ws2.lastRow.number}`);
  ws2.getRow(ws2.lastRow.number).height = 32;

  const dailyHeader = ws2.addRow(["Tarikh", "Pesanan", "", "Pendapatan (RM)"]);
  dailyHeader.eachCell((cell) => {
    cell.font = HEADER_FONT;
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: TEAL_LIGHT } };
    cell.alignment = { vertical: "middle", horizontal: "center" };
    cell.border = BORDER;
  });

  const sortedDays = Object.entries(dailyMap).sort((a, b) => b[0].localeCompare(a[0]));
  for (const [dayKey, dayAgg] of sortedDays) {
    const row = ws2.addRow([dayKey, dayAgg.totalOrders, "", `RM ${dayAgg.totalFare.toFixed(2)}`]);
    row.eachCell((cell) => {
      cell.font = CELL_FONT;
      cell.alignment = { vertical: "middle", horizontal: "center" };
      cell.border = BORDER;
    });
  }

  // --- Rider summary ---
  ws2.addRow([]);
  ws2.addRow(["PRESTASI RIDER"]).eachCell((cell) => {
    cell.font = { name: "Calibri", bold: true, size: 14, color: { argb: WHITE } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: TEAL } };
    cell.alignment = { vertical: "middle", horizontal: "center" };
  });
  ws2.mergeCells(`A${ws2.lastRow.number}:D${ws2.lastRow.number}`);
  ws2.getRow(ws2.lastRow.number).height = 32;

  const riderHeader = ws2.addRow(["Rider", "Pesanan", "", "Jumlah (RM)"]);
  riderHeader.eachCell((cell) => {
    cell.font = HEADER_FONT;
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: TEAL_LIGHT } };
    cell.alignment = { vertical: "middle", horizontal: "center" };
    cell.border = BORDER;
  });

  const sortedRiders = Object.entries(riderMap).sort((a, b) => b[1].totalFare - a[1].totalFare);
  for (const [, riderAgg] of sortedRiders) {
    const row = ws2.addRow([riderAgg.name, riderAgg.totalOrders, "", `RM ${riderAgg.totalFare.toFixed(2)}`]);
    row.eachCell((cell) => {
      cell.font = CELL_FONT;
      cell.alignment = { vertical: "middle", horizontal: "center" };
      cell.border = BORDER;
    });
  }

  ws2.getColumn(1).width = 16;
  ws2.getColumn(2).width = 12;
  ws2.getColumn(3).width = 8;
  ws2.getColumn(4).width = 18;

  // Save
  await workbook.xlsx.writeFile(filePath);
  console.log(`✅ Excel exported to ${filePath}`);

  // --- Delete delivered orders from Firestore ---
  const batchSize = 500;
  const docs = snapshot.docs;
  for (let i = 0; i < docs.length; i += batchSize) {
    const batch = db.batch();
    const batchDocs = docs.slice(i, i + batchSize);
    for (const doc of batchDocs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    console.log(`🗑️ Deleted ${batchDocs.length} orders...`);
  }

  console.log(`✅ Done. Deleted ${docs.length} orders total. File saved as: ${path.basename(filePath)}`);
}

main().catch(console.error);
