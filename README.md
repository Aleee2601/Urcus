# Urcuș — antrenamente + Garmin (iPhone & Mac)

Aplicație personală SwiftUI: plan de antrenament, istoric și statistici din Garmin Connect (Personal API).

## Ce face
- **Azi**: antrenamentul zilei, progresul pe săptămână (km, D+, timp, cât din plan ai făcut), ce urmează și ultima activitate.
- **Plan**: generator de plan progresiv până la cursă (bază → dezvoltare → vârf → descărcare, săptămână de refacere la fiecare a 4-a). Activitățile din Garmin bifează automat antrenamentul din aceeași zi. Swipe sau click dreapta pentru făcut / sărit / șters. Poți edita orice.
- **Istoric**: toate activitățile pe luni, cu căutare, filtru pe sport și pagină de detalii (ritm, D+, puls, calorii, link spre Garmin Connect).
- **Statistici**: grafic pe ultimele 12 săptămâni (km / D+ / ore pe sport), totaluri pe an și cât de mult ai respectat planul.
- **Setări**: cheia Garmin (stă în Keychain), sincronizare, explorator de date brute (somn, HRV, Body Battery, puls, stres).

## Noutăți
- **Plan configurabil**: alegi zilele fiecărui antrenament și dealul tău; **Recalculează de aici** (din meniul planului) reface antrenamentele nefăcute pornind de la ce ai alergat în ultimele 4 săptămâni.
- **Potrivire mai atentă**: o activitate bifează un antrenament doar dacă are cel puțin 40% din distanța / urcarea / durata țintă.
- **Odihnă pe ecranul Azi**: semafor din somn, HRV și Body Battery (dacă Garmin le trimite; altfel cardul nu apare).
- **Cheia Garmin**: avertisment pe Azi și notificare cu 14 și 3 zile înainte să expire.
- **Copie de siguranță**: Setări → exportă / importă planurile ca fișier JSON.
- **Widget** pe iPhone cu antrenamentul de azi (citește din App Group `group.ro.alexandra.urcus`).
- **Teste**: ⌘U în Xcode (`UrcusTests`).

## Design
Stilul „Amurg alpin”: fundal verde-noapte, accent piersică, mov pentru urcare, salvie pentru „făcut”, fontul Manrope (inclus, licență OFL în `Resources/Fonts`).
- **iPhone**: bară de tab-uri plutitoare, cardul zilei cu creasta de munte, banda săptămânii, inel de progres.
- **Mac**: meniu lateral, planul ca un calendar cu toate săptămânile, istoric cu listă + detaliu alături, statistici late cu perioadă selectabilă.
- Culorile și componentele stau în `Design/Theme.swift` și `Design/DesignKit.swift`.

## Cum o pornești
1. Dezarhivează și deschide `Urcus.xcodeproj` în Xcode (16 sau mai nou).
2. Click pe proiectul **Urcus** → target **Urcus** → **Signing & Capabilities** → la **Team** alege contul tău Apple (Personal Team).
   - Dacă Xcode spune că bundle ID-ul e luat, schimbă `ro.alexandra.urcus` cu altceva unic.
3. **Pe Mac**: sus, la destinație, alege **My Mac** → ⌘R.
4. **Pe iPhone**: conectează telefonul prin cablu, alege-l ca destinație → ⌘R.
   - Prima dată: pe iPhone, Settings → Privacy & Security → **Developer Mode** → ON (repornește).
   - Apoi Settings → General → VPN & Device Management → încrede-te în profilul tău de dezvoltator.
   - Cu cont Apple gratuit, aplicația de pe iPhone expiră după 7 zile: o repornești din Xcode și datele rămân.

## Cheia Garmin
1. Pe connect.garmin.com (web): Setări → **Personal API Key** → Create Key → alege expirarea (recomand 1 an).
2. În aplicație: **Setări** → lipește cheia → Salvează. Aplicația testează conexiunea și aduce ultimul an de activități.
3. Pune cheia pe fiecare dispozitiv (iPhone și Mac au fiecare baza lor de date locală).

Cheia Personal API poate doar **citi** date. Garmin nu permite trimiterea de antrenamente pe ceas decât prin programul pentru firme (Training API).

## Dacă Xcode nu deschide proiectul
Fișierul de proiect e scris pentru Xcode 16+. Ca variantă de rezervă:
```
brew install xcodegen
cd Urcus
xcodegen
```
Asta regenerează `Urcus.xcodeproj` din `project.yml`.

## Structură
```
Urcus/
  UrcusApp.swift          – pornire + tab-uri
  Model/                  – SwiftData (activități, planuri, antrenamente), generatorul de plan
  Garmin/                 – client Personal API, Keychain, sincronizare + potrivire automată
  Design/                 – tema (culori, font) și componentele vizuale
  Views/                  – ecranele (iPhone și Mac în aceleași fișiere)
  Resources/Fonts/        – Manrope
  Support/                – formatări în română, calendar cu luni prima zi
```
