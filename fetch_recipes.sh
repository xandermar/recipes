#!/bin/bash

# Configuration
REPO_URL="https://github.com/xandermar/articles-cooking.git"
TMP_DIR="recipes_tmp"
OUTPUT_DIR="docs"
INDEX_FILE="${OUTPUT_DIR}/index.html"
LINKS_FILE="recipe_links.tmp"
DEFAULT_IMAGE_URL="https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=600&q=80"

# Step 0: Load .env file for Unsplash API key
if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ .env file not found. Please create it and add UNSPLASH_ACCESS_KEY."
  exit 1
fi

if [[ -z "$UNSPLASH_ACCESS_KEY" ]]; then
  echo "❌ UNSPLASH_ACCESS_KEY not set in .env"
  exit 1
fi

# Step 1: Prepare output directory
mkdir -p "$OUTPUT_DIR"
find "$OUTPUT_DIR" -type f -name '*.html' -delete
cp index.html "$INDEX_FILE"

# Step 2: Clone GitHub repo with markdown recipes
rm -rf "$TMP_DIR"
git clone --depth=1 "$REPO_URL" "$TMP_DIR"

# Step 3: Check for pandoc
if ! command -v pandoc &> /dev/null; then
  echo "❌ pandoc not installed"
  exit 1
fi

# Footer HTML generator
generate_footer() {
cat <<EOF
  <footer class="mt-5 text-white text-center py-4" style="background: linear-gradient(to right, #ff9800, #ff5722);">
    <div class="container">
      <p class="mb-1 fw-bold" style="font-size: 1.2rem;">🍴 Made with love and butter • Tasty Adventures in Cooking</p>
      <p class="mb-0">© $(date +%Y) Delicious Recipes</p>
    </div>
  </footer>
EOF
}

# Unsplash image fetcher
get_image_url_for_recipe() {
  local title="$1"
  local query=$(echo "$title" | sed 's/ /-/g')

  response=$(curl -s "https://api.unsplash.com/search/photos?query=${query}&orientation=landscape&per_page=1&client_id=$UNSPLASH_ACCESS_KEY")

  if command -v jq &> /dev/null; then
    image_url=$(echo "$response" | jq -r '.results[0].urls.regular')
  else
    image_url=$(echo "$response" | grep -o '"regular":"[^"]*' | sed 's/"regular":"//')
  fi

  if [[ -z "$image_url" || "$image_url" == "null" ]]; then
    echo "$DEFAULT_IMAGE_URL"
  else
    echo "$image_url"
  fi
}

# Step 4: Generate recipe links for homepage
echo '      <h2 class="mb-4 text-primary">Featured Recipes</h2>' > "$LINKS_FILE"
echo '      <div class="row">' >> "$LINKS_FILE"

# Step 5: Process each markdown recipe
find "$TMP_DIR" -name '*.md' | while read -r mdfile; do
  filename=$(basename "$mdfile" .md)
  title="$filename"
  slug=$(echo "$filename" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
  htmlfile="${OUTPUT_DIR}/${slug}.html"
  IMAGE_URL=$(get_image_url_for_recipe "$title")

  echo "✅ Processing $title"

  body=$(pandoc "$mdfile" -f markdown -t html)

  {
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <style>
    body {
      background-color: #fff8f0;
      font-family: 'Segoe UI', sans-serif;
      padding-top: 0;
      margin: 0;
    }
    header {
      background: linear-gradient(to right, #ff5722, #ff9800);
      color: white;
      padding: 2rem 1rem;
      text-align: center;
      box-shadow: 0 4px 10px rgba(0,0,0,0.2);
    }
    header h1 {
      margin: 0;
      font-size: 3rem;
      font-weight: bold;
      text-shadow: 2px 2px 6px rgba(0,0,0,0.4);
    }
    .container {
      max-width: 700px;
      margin-top: 2rem;
    }
    .card-img-top {
      width: 100%;
      height: 200px;
      object-fit: cover;
    }
  </style>
</head>
<body>
  <header>
    <h1>$title</h1>
  </header>
  <div class="container">
    <p><a href="index.html" class="btn btn-warning mt-4">← Back to Recipes</a></p>
    $body
    <p><a href="index.html" class="btn btn-warning mt-4">← Back to Recipes</a></p>
  </div>
EOF

    generate_footer
    echo "</body>"
    echo "</html>"
  } > "$htmlfile"

  # Add Bootstrap card to index
  cat >> "$LINKS_FILE" <<EOF
      <div class="col-md-4 mb-4">
        <div class="card h-100 shadow">
          <img src="$IMAGE_URL" class="card-img-top" alt="$title">
          <div class="card-body d-flex flex-column">
            <h5 class="card-title">$title</h5>
            <a href="${slug}.html" class="btn btn-warning mt-auto">View Recipe</a>
          </div>
        </div>
      </div>
EOF

done

echo '      </div>' >> "$LINKS_FILE"

# Step 6: Inject links into docs/index.html
if [[ -f "$INDEX_FILE" ]]; then
  awk '
    /<section id="recipes">/ { print; print "%%START_RECIPE_LINKS%%"; skip=1; next }
    /<\/section>/ { print "%%END_RECIPE_LINKS%%"; print; skip=0; next }
    !skip { print }
  ' "$INDEX_FILE" > "${INDEX_FILE}.tmp"

  mv "${INDEX_FILE}.tmp" "$INDEX_FILE"

  sed -i '' -e "/%%START_RECIPE_LINKS%%/,/%%END_RECIPE_LINKS%%/{
    /%%START_RECIPE_LINKS%%/r $LINKS_FILE
    /%%START_RECIPE_LINKS%%/,/%%END_RECIPE_LINKS%%/d
  }" "$INDEX_FILE"

  if ! grep -q "Made with love and butter" "$INDEX_FILE"; then
    echo "" >> "$INDEX_FILE"
    generate_footer >> "$INDEX_FILE"
    echo "</body></html>" >> "$INDEX_FILE"
  fi

  echo "✅ ${INDEX_FILE} updated with fixed-size recipe cards and footer."
else
  echo "⚠️ ${INDEX_FILE} not found"
fi

# Step 7: Cleanup
rm -rf "$TMP_DIR" "$LINKS_FILE"
