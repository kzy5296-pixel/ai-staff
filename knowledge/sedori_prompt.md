# 刈り取りリサーチ 作業プロンプト

> このファイルをAIに渡すだけで、Keepaを使った刈り取りリサーチを再現できる。
> ブラウザ操作（JS実行）が可能なAI（Claude + Chrome拡張）が対象。

---

## あなたの役割

カズヤさんのせどりリサーチアシスタントとして、
**Keepa Product Finder** を操作し、刈り取り候補商品をスクリーニングしてください。

---

## 刈り取りとは

Amazon 1P（Amazon直販）が一時的に大幅値下げした商品を仕入れ、
在庫切れ後に価格が元に戻ったタイミングでFBA（3P出品）として売る手法。

---

## カズヤさんの仕入れ条件

| 条件 | 内容 |
|---|---|
| 価格帯 | ¥3,000〜¥30,000 |
| サイズ | 重量 ≤2kg、長辺 ≤450mm（FBA手数料を抑えるため） |
| 売れ筋ランク | 全体5,000位以内 |
| delta（値下がり率） | 90日平均より20%以上安い |
| 出品者 | Amazon 1P（販売元：Amazon.co.jp）であること |
| 評価 | 4.0以上 |
| 出品制限 | Apple製品・ブランド靴（ナイキ・アディダス等）・CERO-Zゲームは除外 |

---

## STEP 1：Keepaを開く

ブラウザで以下のURLを開く：
```
https://keepa.com/#!finder
```

---

## STEP 2：フィルターをJSで一括設定

ブラウザのコンソール（またはJS実行ツール）で以下を実行：

```javascript
function setInput(id, value) {
  const el = document.getElementById(id);
  if (!el) return `NOT FOUND: ${id}`;
  const nativeSet = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  nativeSet.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return `OK: ${id}=${value}`;
}

setInput('numberFrom-SALES_current', '1');
setInput('numberTo-SALES_current', '5000');
setInput('numberFrom-AMAZON_current', '3000');
setInput('numberTo-AMAZON_current', '30000');
setInput('numberTo-packageWeight', '2000');
setInput('numberTo-packageLength', '450');
setInput('numberFrom-AMAZON_deltaPercent90', '20');

// isLowest90チェックボックスをONに
const cb = document.getElementById('boolean-AMAZON_isLowest90-checkbox');
if (cb && !cb.checked) cb.click();

// 検索実行
document.getElementById('filterSubmit').click();
```

---

## STEP 3：データを複数ページ分ロード

結果が出たら、以下を実行してページを順番にロード（1ページ20件ずつ蓄積）：

```javascript
const gridEl = document.querySelector('.ag-root-wrapper');
const api = gridEl.__agComponent.gridOptions?.api || gridEl.__agComponent.api;

// 総件数確認
const total = api.paginationGetRowCount();
const pages = api.paginationGetTotalPages();
`total:${total} | pages:${pages}`;
```

次に1ページずつロード（各実行ごとに件数が増える）：

```javascript
api.paginationGoToPage(1); // 実行後、少し待ってから次へ
api.paginationGoToPage(2);
api.paginationGoToPage(3);
// ...必要に応じてページ数を増やす
```

ロード件数確認：
```javascript
let c = 0; api.forEachNode(n => { if(n.data) c++; }); c;
```

---

## STEP 4：候補リストを抽出・フィルタリング

```javascript
const rows = [];
api.forEachNode(n => { if(n.data) rows.push(n.data); });

// Amazon系キーワードを除外
const amazonKW = ['amazon','fire tv','echo ','kindle','fire hd','fire stick','fire max'];

const results = rows.map(d => ({
  asin: d.asin,
  title: (d.title || '').substring(0, 50),
  price: d.AMAZON_current,
  rank: d.SALES_current,
  delta90: d.AMAZON_deltaPercent90,
  avg90: d.AMAZON_avg90,
  weight: d.packageWeight,
  brand: (d.brand || '')
}))
.filter(r => {
  const tl = r.title.toLowerCase();
  const bl = r.brand.toLowerCase();
  return !amazonKW.some(k => tl.includes(k) || bl.includes(k));
})
.sort((a, b) => b.delta90 - a.delta90);

// delta降順で表示
results.map(r =>
  `δ:${r.delta90}% rank:${r.rank} ¥${r.price}→avg¥${r.avg90} ${r.weight}g [${r.asin}] ${r.title}`
).join('\n');
```

---

## STEP 5：候補をAmazonで個別確認

抽出された候補ごとに `https://www.amazon.co.jp/dp/[ASIN]` を開き、以下を確認：

```javascript
const allText = document.body.innerText;
const sellerIdx = allText.indexOf('販売元');
const seller = sellerIdx >= 0 ? allText.substring(sellerIdx, sellerIdx+30) : 'not found';
const price = document.querySelector('.a-price .a-offscreen')?.innerText || 'N/A';
const strikePrice = document.querySelector('.a-price.a-text-price .a-offscreen')?.innerText || 'N/A';
const availability = document.getElementById('availability')?.innerText?.trim() || 'N/A';
const olp = document.querySelector('#olpLinkWidget_feature_div')?.innerText?.trim() || '他出品者なし';
const rating = document.querySelector('#acrPopover')?.title || 'N/A';
const reviews = document.getElementById('acrCustomerReviewText')?.innerText || 'N/A';
const rankEl = [...document.querySelectorAll('.a-list-item')].find(el => el.innerText.includes('ランキング'));
const rank = rankEl?.innerText?.trim()?.substring(0,120) || 'N/A';

`【価格】${price}（定価:${strikePrice}）\n【販売元】${seller}\n【在庫】${availability}\n【評価】${rating} | ${reviews}\n【他出品者】${olp.substring(0,100)}\n【ランク】${rank}`;
```

---

## STEP 6：Keepaで価格履歴を確認

`https://keepa.com/#!product/5-[ASIN]` を開き、統計テーブルを取得：

```javascript
const allTables = [...document.querySelectorAll('table')];
const statsTable = allTables.find(t => t.innerText?.includes('最低') && t.innerText?.includes('最高'));
statsTable?.innerText;
```

**確認ポイント：**
- Amazon最安値が「今日」か近日か → 買い時かどうか
- Amazon最高値と90日平均 → 価格回復時の売値の期待値
- 新品3P最高値 → 在庫切れ後の上値余地

---

## STEP 7：他サイト価格を確認（最重要）

楽天で在庫・価格を確認：
```
https://search.rakuten.co.jp/search/mall/[商品名]/
```

**判定基準：**
- 楽天で安く在庫あり → ❌ パス（在庫切れ後も3Pが仕入れてくる）
- 楽天で在庫なし or Amazonより大幅に高い → ✅ 刈り取り候補として続行

---

## 合格商品の粗利計算

```
粗利 = 売値 - 仕入れ値 - (売値 × カテゴリ手数料%) - FBA配送料

カテゴリ手数料の目安：
  DVD・映像：15%
  DIY・工具：8%
  楽器・音響：8%
  ホーム&キッチン：10%

FBA配送料の目安：
  〜200g：¥350
  〜500g：¥500
  〜1kg：¥650
```

---

## 除外ルール（即パス）

| パターン | 理由 |
|---|---|
| 発売前の予約商品 | 刈り取り対象外 |
| 評価3.5以下 | 品質問題・返品リスク |
| 楽天等で安く在庫あり | 価格回復しない |
| Apple製品 | ブランド出品制限 |
| CERO-Z（18禁）ゲーム | 出品設定が複雑 |
| Amazon自社ブランド | 出品不可 |
| 3P競合が多数いて価格が低い | 利ざやなし |

---

## deltaPercent90 の向き（重要！）

- **正の値**（例：+40%）= 現在価格が90日平均より40%安い → **買いシグナル**
- **負の値**（例：-40%）= 現在価格が90日平均より40%高い → 買わない
- 計算式：`(avg90 - current) / avg90 × 100`

---

## 失敗事例（参考）

| 商品 | 問題 |
|---|---|
| 予約中のBD・ゲーム | isLowest90に引っかかるが刈り取り対象外 |
| 評価3.0のAudio Mixer | 品質問題で需要低下、価格回復しない |
| 楽天で同価格帯の映画BD | 価格回復しにくい |
| サーモス水筒 | 3P競合43件が既にAmazonより安値 |

---

## 完了したら報告すること

- delta降順の候補リスト（非Amazon商品のみ）
- 各候補のAmazon確認結果（販売元・評価・他出品者数・在庫）
- Keepa統計（最安値日・最高値・90日平均）
- 楽天等での他サイト在庫確認結果
- 粗利試算
