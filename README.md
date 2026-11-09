# Utilitka

Монітор активності для рядка меню macOS. Показує завантаження процесора, пам'ять, акумулятор, диск, мережу й температуру, а програми, що гальмують Mac, дозволяє завершити в один клік.

*A menu bar activity monitor for macOS: CPU, memory, battery, disk, network and temperature, with one-click quitting of apps that slow your Mac down. English summary at the end.*

## Можливості

- **Рядок меню:** температура процесора, завантаження CPU та пам'яті. Що саме показувати, вибирається в налаштуваннях.
- **Процесор:** графік «користувач / система», температура чипа, найбільш навантажені процеси з середнім значенням за 5 секунд.
- **Пам'ять:** програми, закріплена й стиснута пам'ять, навантаження, підкачка, найбільші споживачі.
- **Живлення:** заряд, здоров'я акумулятора, цикли, ємність, температура.
- **Огляд:** диск, пам'ять, акумулятор, процесор, мережа, час роботи.
- **Завершення процесів:** звичайне або примусове, з підтвердженням.
- Працює у фоні, займає близько 1% CPU, без іконки в Dock. Можна запускати при вході в систему.

## Вимоги

- macOS 26 або новіша.
- Mac з Apple Silicon для показу температури. Решта працює й на Intel.

## Встановлення

1. Завантажте `Utilitka.zip` зі сторінки [Releases](../../releases) і розпакуйте.
2. Перетягніть `Utilitka.app` у папку «Програми».
3. Відкрийте застосунок. Під час першого запуску macOS попередить, що не може перевірити розробника: застосунок не нотаризовано в Apple.
4. Щоб дозволити запуск: **Системні параметри → Приватність і безпека** → внизу біля повідомлення про Utilitka натисніть **«Усе одно відкрити»** і підтвердіть паролем.

Цілісність архіву можна перевірити: контрольна сума SHA-256 опублікована поруч, у файлі `Utilitka.zip.sha256`.

```bash
shasum -a 256 Utilitka.zip
```

## Збірка з коду

Потрібні Xcode 26+ та [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Utilitka.xcodeproj
```

Далі в Xcode натисніть ⌘R. Готовий архів для релізу збирає скрипт:

```bash
./scripts/build-release.sh
```

## Приватність і безпека

- **Нічого не відправляється в інтернет.** Utilitka не має мережевого коду, аналітики, телеметрії чи оновлень через мережу. Усі дані читаються локально з системи й ніде не зберігаються, крім ваших налаштувань.
- **Чому без пісочниці (App Sandbox).** Пісочниця забороняє бачити й завершувати чужі процеси, а без цього монітор активності неможливий. Через це застосунок не може бути в App Store.
- **Завершує тільки ваші процеси.** Utilitka працює з правами звичайного користувача й не має помічника з правами адміністратора. Системні процеси (WindowServer, kernel_task тощо) вона не бачить і не може зупинити.
- **Приватні API.** Температура читається через функції macOS, яких немає в публічному SDK. Їх використовують Stats та iStat Menus. Якщо Apple змінить ці функції, зникне лише показ температури.
- **Код відкритий.** Перевірити, що робить застосунок, можна прямо в цьому репозиторії. Збираючи з коду самостійно, ви не залежите від готових архівів.

## Ліцензія

[MIT](LICENSE): можна вільно використовувати, змінювати й поширювати.

---

## English

Utilitka is a macOS menu bar app that shows CPU load (with a 5-second process average), memory, battery health, disk, network and Apple Silicon temperatures, and lets you quit heavy apps with a confirmation. It runs in the background at about 1% CPU.

**Install:** download `Utilitka.zip` from Releases, move the app to Applications, open it, then allow it in *System Settings → Privacy & Security → Open Anyway* (the app is not notarized).

**Privacy:** no network access, no analytics, nothing leaves your Mac. It runs outside the App Sandbox because listing and quitting other processes is impossible inside it, and it can only quit processes owned by your user. Temperatures use private macOS functions also used by Stats and iStat Menus.

**Build:** Xcode 26+, `brew install xcodegen && xcodegen generate`, then run in Xcode, or `./scripts/build-release.sh` for a release zip.

License: MIT.
