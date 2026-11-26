# polyrutina
[русское описание](#russian)

polyrutina is an application for keeping a «field journal», implemented in Flutter and adapted for operation in Android, Windows, Linux, macOS, iOS and web.

it serves both for collecting notes and planning tasks and for coordinating repeated sequences of actions called **routines**, which in this context are understood as ordered sets of stages, each of which can be timed with a timer and supplied with a comment, a checklist, media files, geolocation points and attached documents.

the **intent** arose from the need to preserve details during group work in a two-century garden,— for oneself in the future and for those who will come later,— by capturing circumstances, unexpected details, outcomes, and also the tools and materials used there, which is intended to facilitate the preparation and execution of future tasks, to help novices in learning and to protect against repetition of errors already committed.

at present, **field work** is being tested on Android and Windows; export and import of routines have been implemented, while server synchronization remains at the design stage,— its testing is expected by Christmas.

**architecturally**, the application is executed in Dart using the Flutter framework. data storage is carried out locally in the DBMS SQLite (an embedded database) by means of the Drift library (an object-relational mapping tool); geolocation binding is implemented through flutter_map with OpenStreetMap tiles that do not require access keys (pubspec.yaml). for work with media, image_picker, file_picker, record, video_player and just_audio are employed; export and import of routines are performed through zip archives (the archive library); notifications and permissions are handled by flutter_local_notifications and permission_handler. configuration parameters and texts are moved into the external files assets/i18n.json and assets/defaults.json.

as for **redundancy of functionality** for a simple note journal, it is precisely the combination of stages, media and geodata that distinguishes a «field journal» from an ordinary note, and this combination is dictated by practice. the modular structure (tabs routines/days) and localization soften the entry threshold.

as for competition with **existing tools** (Notion, Evernote, specialized trackers), the application does not compete but occupies the niche of tools oriented toward binding to place and repeated work cycles, which the aforementioned tools do not fully offer.

the architecture, data structure and user scenarios are **developed by a human**, which is confirmed by the commit history and the organization of the repository: the use of neural networks does not diminish the value of the result,— the author understands and controls the codebase.

being conceived as a «place journal», polyrituna can potentially serve as a tool for **preservation of local knowledge**,— for example, for repair, construction or agricultural work, where the experience of predecessors is often lost: in this sense the application is akin to naturalists’ field notes or engineering journals, and its **value increases as data accumulate**.

further steps will be connected with testing server interaction and with determining scenarios of joint work, which at present remain **at the stage of comprehending the artel (cooperative) approach**.

---

<a name="russian">полирутина</a>,— приложение для ведения «бортового журнала», исполненное на Flutter и приспособленное к работе в Android, Windows, Linux, Macos, iOS и web.

оно служит и для сбора заметок/ планирования задач, и для согласования повторяемых последовательностей действий, именуемых **рутинами**, кои в данном контексте понимаются как упорядоченные совокупности этапов, каждый из которых может быть замерен таймером, снабжён комментарием, контрольным списком, медиафайлами, точками геолокации и прикреплёнными документами.

**замысел** возник из потребности сохранять детали при групповой работе в двухвековом саду,— для себя в будущем и для тех, кто придёт позже,— запечатлев обстоятельства, неожиданные подробности, исходы, а также инструменты и материалы, там использованные, что призвано облегчить подготовку и выполнение будущих задач, помочь новичкам в обучении и уберечь от повторения уже совершённых ошибок.

ныне **полевая работа** обкатывается на Android и Windows; экспорт и импорт рутин реализованы, серверная синхронизация пребывает в стадии проектирования,— её обкатка предполагается к Рождеству.

**архитектурно** приложение исполнено на Dart с использованием фреймворка Flutter. хранение данных осуществляется локально в СУБД SQLite (встраиваемая база данных) посредством библиотеки Drift (средство объектно-реляционного отображения); геолокационная привязка реализована через flutter_map с тайлами OpenStreetMap, не требующими ключей доступа (pubspec.yaml). для работы с медиа задействованы image_picker, file_picker, record, video_player и just_audio; экспорт и импорт рутин выполняются через zip-архивы (библиотека archive); уведомления и разрешения обрабатываются flutter_local_notifications и permission_handler. конфигурационные параметры и тексты вынесены во внешние файлы assets/i18n.json и assets/defaults.json.

**избыточность функционала** для простого журнала заметок? именно совокупность этапов, медиа и геоданных отличает «полевой журнал» от обычной заметки, и эта совокупность продиктована практикой. модульная структура (вкладки routines/ days) и локализация смягчают порог вхождения.

конкуренция с **существующими инструментами** (notion, evernote, специализированные трекеры)? приложение не конкурирует, а занимает нишу ориентированных на привязку к месту и повторяемые рабочие циклы, чего означенные инструменты в полной мере не предлагают.

архитектура, структура данных и пользовательские сценарии **разработаны человеком**, что подтверждается историей коммитов и организацией репозитория: применение нейросетей не умаляет ценности результата,— автор понимает и контролирует кодовую базу.

будучи задуманным как «журнал места», polyrituna потенциально может служить инструментом **сохранения локального знания**,— например, для ремонта, строительства или сельскохозяйственных работ, где опыт предшественников зачастую утрачивается: в этом смысле приложение сродни полевым записям натуралистов или инженерным журналам, а его **ценность возрастает по мере накопления данных**.

дальнейшие шаги будут связаны с обкаткой серверного взаимодействия и с определением сценариев совместной работы, которые ныне пребывают **в стадии осмысления артельного подхода**.
