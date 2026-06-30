#!/bin/bash
set -euo pipefail

echo "🔧 Configuration de LyricSync..."

if ! command -v xcodegen &> /dev/null; then
    echo "⚠️  XcodeGen n'est pas installé. Installation..."
    brew install xcodegen
fi

cd "$(dirname "$0")"
xcodegen generate --project .

echo ""
echo "✅ Projet généré."
echo ""
echo "━━━ Première utilisation ━━━"
echo ""
echo "1. Ouvre project.yml et remplace DEVELOPPEMENT_TEAM: \"\""
echo "   par ton Team ID (Xcode > Settings > Accounts > ton Apple ID)"
echo "   Exemple: DEVELOPPEMENT_TEAM: \"ABC123DEFG\""
echo ""
echo "2. Regénère le projet :   ./setup.sh"
echo ""
echo "3. Ouvre LyricSync.xcodeproj dans Xcode"
echo ""
echo "4. iOS : Build et lance sur iPhone (le Simulator ne supporte pas la"
echo "   reconnaissance vocale on-device)"
echo "   macOS : Sélectionne \"My Mac\" comme destination et build"
echo ""
echo "⚠️  Le projet cible iOS 17+ et macOS 14+ (multiplatform SwiftUI)"
echo "⚠️  Sur macOS : configure un dossier de sortie par défaut dans"
echo "    l'onglet Réglages pour sauvegarder directement M4A + LRC"
