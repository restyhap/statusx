import Foundation

/// 界面支持的语言（9 种，不含日语）。
/// 顺序即 `Str` 里每条文案的列顺序：en / zh-Hans / zh-Hant / ko / de / fr / es / pt / ru
enum AppLang: String, CaseIterable {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ko
    case de
    case fr
    case es
    case pt
    case ru

    /// 语言选择里显示的名字：一律用它自己的语言写
    var nativeName: String {
        switch self {
        case .en:     return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ko:     return "한국어"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        case .es:     return "Español"
        case .pt:     return "Português"
        case .ru:     return "Русский"
        }
    }

    /// 系统首选语言 → 支持的语言（找不到就用英文）
    static func detect() -> AppLang {
        for id in Locale.preferredLanguages {
            let l = id.lowercased()
            if l.hasPrefix("zh-hant") || l.hasPrefix("zh-tw") || l.hasPrefix("zh-hk") { return .zhHant }
            if l.hasPrefix("zh") { return .zhHans }
            if let hit = allCases.first(where: { l.hasPrefix($0.rawValue) }) { return hit }
        }
        return .en
    }

    static func from(_ raw: String?) -> AppLang? {
        guard let raw, !raw.isEmpty else { return nil }
        return AppLang(rawValue: raw)
    }

    var column: Int { AppLang.allCases.firstIndex(of: self) ?? 0 }
}

enum L10n {
    /// 当前语言；配置里没写就跟随系统
    static var lang: AppLang = .detect()

    static func apply(_ cfg: Config) {
        lang = AppLang.from(cfg.language) ?? .detect()
    }

    /// 一条文案的 9 种语言取值，按当前语言取列；列不够时退回英文
    static func pick(_ values: [String]) -> String {
        let i = lang.column
        return i < values.count ? values[i] : values[0]
    }
}

/// 所有界面文案。字体/布局仍由各页面负责，这里只放文字。
enum Str {

    // MARK: 窗口 / 左栏

    static var winTitle: String {
        L10n.pick(["StatusX Preferences", "StatusX 偏好设置", "StatusX 偏好設定", "StatusX 환경설정",
                   "StatusX Einstellungen", "Préférences StatusX", "Preferencias de StatusX",
                   "Preferências do StatusX", "Настройки StatusX"])
    }

    static var navGeneral: String {
        L10n.pick(["General", "通用", "一般", "일반", "Allgemein", "Général", "General", "Geral", "Общие"])
    }

    static var navApps: String {
        L10n.pick(["Apps", "应用", "應用程式", "앱", "Apps", "Apps", "Apps", "Apps", "Приложения"])
    }

    static var navWidget: String {
        L10n.pick(["Status Items", "状态组件", "狀態元件", "상태 항목", "Statusobjekte",
                   "Éléments de statut", "Elementos de estado", "Itens de estado", "Элементы статуса"])
    }

    // MARK: 菜单栏（显示图标 / 拖动排序）

    static var noteAddApps: String {
        L10n.pick(["Click an icon to show it in the menu bar (max 10).",
                   "点击图标把它放到菜单栏（最多 10 个）。",
                   "點擊圖示把它放到選單列（最多 10 個）。",
                   "아이콘을 클릭하면 메뉴 막대에 표시됩니다(최대 10개).",
                   "Symbol anklicken, um es in die Menüleiste zu legen (max. 10).",
                   "Cliquez une icône pour l'afficher dans la barre (10 max).",
                   "Haz clic en un icono para mostrarlo en la barra (máx. 10).",
                   "Clique num ícone para o mostrar na barra (máx. 10).",
                   "Нажмите значок, чтобы показать его в строке меню (макс. 10)."])
    }

    // MARK: 被系统折叠时的提示

    static var foldedTitle: String {
        L10n.pick(["StatusX is hidden by the menu bar",
                   "StatusX 被菜单栏收起了",
                   "StatusX 被選單列收起了",
                   "StatusX가 메뉴 막대에서 가려졌습니다",
                   "StatusX wird von der Menüleiste verdeckt",
                   "StatusX est masqué par la barre des menus",
                   "La barra de menús ha ocultado StatusX",
                   "O StatusX foi ocultado pela barra de menus",
                   "StatusX скрыт строкой меню"])
    }

    static var foldedBody: String {
        L10n.pick(["There is not enough room left in the menu bar, so macOS moved StatusX into the overflow area.\n\n• Hold ⌘ and drag StatusX to the right side of the menu bar, or\n• show fewer components in Settings, or\n• remove a few menu bar icons with ⌘-drag.",
                   "菜单栏已经没有空位，macOS 把 StatusX 收进了溢出区（栏上那个「«」或「»」）。\n\n• 按住 ⌘ 把 StatusX 拖到菜单栏右侧，或\n• 到设置里少显示几个组件，或\n• 用 ⌘ 拖走一些别的菜单栏图标腾出位置。",
                   "選單列已經沒有空位，macOS 把 StatusX 收進了溢出區（列上那個「«」或「»」）。\n\n• 按住 ⌘ 把 StatusX 拖到選單列右側，或\n• 到設定裡少顯示幾個元件，或\n• 用 ⌘ 拖走一些別的選單列圖示騰出位置。",
                   "메뉴 막대에 공간이 없어 macOS가 StatusX를 오버플로 영역으로 옮겼습니다.\n\n• ⌘를 누른 채 StatusX를 메뉴 막대 오른쪽으로 끌거나,\n• 설정에서 표시할 구성 요소를 줄이거나,\n• 다른 메뉴 막대 아이콘을 ⌘로 끌어 공간을 만드세요.",
                   "In der Menüleiste ist kein Platz mehr, daher hat macOS StatusX in den Überlaufbereich verschoben.\n\n• ⌘ halten und StatusX nach rechts ziehen, oder\n• in den Einstellungen weniger Komponenten anzeigen, oder\n• einige Menüleisten-Symbole mit ⌘ wegziehen.",
                   "La barra des menus est pleine : macOS a déplacé StatusX dans la zone de débordement.\n\n• Maintenez ⌘ et faites glisser StatusX vers la droite, ou\n• affichez moins de composants dans les réglages, ou\n• retirez quelques icônes de la barre avec ⌘.",
                   "La barra de menús está llena, así que macOS ha movido StatusX al área de desbordamiento.\n\n• Mantén ⌘ y arrastra StatusX a la derecha, o\n• muestra menos componentes en Ajustes, o\n• retira algunos iconos de la barra con ⌘.",
                   "A barra de menus está cheia, por isso o macOS moveu o StatusX para a área de transbordo.\n\n• Mantenha ⌘ e arraste o StatusX para a direita, ou\n• mostre menos componentes nos Ajustes, ou\n• retire alguns ícones da barra com ⌘.",
                   "В строке меню нет места, поэтому macOS убрал StatusX в область переполнения.\n\n• Удерживайте ⌘ и перетащите StatusX правее, или\n• уменьшите число компонентов в настройках, или\n• уберите несколько значков из строки меню с помощью ⌘."])
    }

    static var foldedCompact: String {
        L10n.pick(["Show one item only", "只显示一个组件", "只顯示一個元件", "구성 요소 하나만 표시",
                   "Nur eine Komponente", "N'afficher qu'un élément", "Mostrar solo un elemento",
                   "Mostrar apenas um item", "Оставить один элемент"])
    }

    static var foldedOpenSettings: String {
        L10n.pick(["Open Settings", "打开设置", "開啟設定", "설정 열기", "Einstellungen öffnen",
                   "Ouvrir les réglages", "Abrir Ajustes", "Abrir Ajustes", "Открыть настройки"])
    }

    static var foldedOK: String {
        L10n.pick(["OK", "知道了", "知道了", "확인", "OK", "OK", "OK", "OK", "ОК"])
    }

    // MARK: 状态组件（310px 带子里的指标）

    static var metricCPU: String {
        L10n.pick(["CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "ЦП"])
    }

    static var metricGPU: String {
        L10n.pick(["GPU", "显卡", "顯卡", "GPU", "GPU", "GPU", "GPU", "GPU", "GPU"])
    }

    static var bandGPU: String {
        L10n.pick(["GPU", "显卡", "顯卡", "GPU", "GPU", "GPU", "GPU", "GPU", "GPU"])
    }

    static var valTemp: String {
        L10n.pick(["Temp", "温度", "溫度", "온도", "Temp.",
                   "Temp.", "Temp.", "Temp.", "Темп."])
    }

    static var metricMemory: String {
        L10n.pick(["Memory", "内存", "記憶體", "메모리", "Arbeitsspeicher",
                   "Mémoire", "Memoria", "Memória", "Память"])
    }

    static var metricNetwork: String {
        L10n.pick(["Network", "网络", "網路", "네트워크", "Netzwerk",
                   "Réseau", "Red", "Rede", "Сеть"])
    }

    static var metricBattery: String {
        L10n.pick(["Battery", "电池", "電池", "배터리", "Batterie",
                   "Batterie", "Batería", "Bateria", "Аккумулятор"])
    }

    static var metricDisk: String {
        L10n.pick(["Disk", "硬盘", "硬碟", "디스크", "Festplatte",
                   "Disque", "Disco", "Disco", "Диск"])
    }

    static var metricFan: String {
        L10n.pick(["Fan", "风扇", "風扇", "팬", "Lüfter",
                   "Ventilateur", "Ventilador", "Ventilador", "Вентилятор"])
    }

    // 带子里两行文字的第二行：短名称，越短越好（放不下会裁组件）

    static var bandCPU: String {
        L10n.pick(["CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "ЦП"])
    }

    static var bandMemory: String {
        L10n.pick(["MEM", "内存", "記憶體", "메모", "RAM", "RAM", "RAM", "RAM", "ОЗУ"])
    }

    static var bandNetwork: String {
        L10n.pick(["NET", "网络", "網路", "네트", "NETZ", "RÉS", "RED", "REDE", "СЕТЬ"])
    }

    static var bandDisk: String {
        L10n.pick(["DISK", "硬盘", "硬碟", "디스크", "DISK", "DISQ", "DISCO", "DISCO", "ДИСК"])
    }

    static var bandBattery: String {
        L10n.pick(["BATT", "电池", "電池", "배터", "AKKU", "BATT", "BAT", "BAT", "БАТ"])
    }

    static var bandFan: String {
        L10n.pick(["FAN", "风扇", "風扇", "팬", "LÜFT", "VENT", "VENT", "VENT", "ВЕНТ"])
    }

    static var unavailableFan: String {
        L10n.pick(["idle or not readable on this Mac — hidden.",
                   "当前不转或读不到转速，已隐藏。",
                   "目前不轉或讀不到轉速，已隱藏。",
                   "멈춰 있거나 속도를 읽을 수 없어 숨김.",
                   "steht still oder ist nicht lesbar — ausgeblendet.",
                   "à l'arrêt ou illisible — masqué.",
                   "parado o ilegible — oculto.",
                   "parada ou ilegível — oculto.",
                   "не вращается или недоступен — скрыто."])
    }

    static var unavailableBattery: String {
        L10n.pick(["No readable battery on this Mac — turned off.",
                   "本机没有可读电池，已禁用。",
                   "本機沒有可讀電池，已停用。",
                   "이 Mac에서 배터리를 읽을 수 없습니다 — 꺼짐.",
                   "Kein lesbarer Akku auf diesem Mac — deaktiviert.",
                   "Aucune batterie lisible sur ce Mac — désactivé.",
                   "No hay batería legible en este Mac — desactivado.",
                   "Sem bateria legível neste Mac — desativado.",
                   "Батарея недоступна на этом Mac — отключено."])
    }

    static var autoWidth: String {
        L10n.pick(["Auto width", "自动宽度", "自動寬度", "자동 너비", "Auto-Breite",
                   "Largeur auto", "Ancho automático", "Largura automática", "Авто-ширина"])
    }

    // MARK: 数值项（组件里可选显示的内容）

    static var valUsage: String {
        L10n.pick(["Usage", "用量", "用量", "사용량", "Auslastung",
                   "Utilisation", "Uso", "Uso", "Загрузка"])
    }

    static var valUsagePercent: String {
        L10n.pick(["Usage %", "用量百分比", "用量百分比", "사용률", "Auslastung %",
                   "Utilisation %", "Uso %", "Uso %", "Загрузка %"])
    }

    static var valUsed: String {
        L10n.pick(["Used", "已用", "已用", "사용 중", "Belegt",
                   "Utilisé", "Usado", "Usado", "Занято"])
    }

    static var valFree: String {
        L10n.pick(["Free", "空闲", "閒置", "여유", "Frei",
                   "Libre", "Libre", "Livre", "Свободно"])
    }

    static var valTotal: String {
        L10n.pick(["Total", "总计", "總計", "전체", "Gesamt",
                   "Total", "Total", "Total", "Всего"])
    }

    static var valLoad1: String {
        L10n.pick(["Load 1m", "负载 1 分钟", "負載 1 分鐘", "부하 1분", "Last 1 Min",
                   "Charge 1 min", "Carga 1 min", "Carga 1 min", "Нагрузка 1 мин"])
    }

    static var valLoad5: String {
        L10n.pick(["Load 5m", "负载 5 分钟", "負載 5 分鐘", "부하 5분", "Last 5 Min",
                   "Charge 5 min", "Carga 5 min", "Carga 5 min", "Нагрузка 5 мин"])
    }

    static var valLoad15: String {
        L10n.pick(["Load 15m", "负载 15 分钟", "負載 15 分鐘", "부하 15분", "Last 15 Min",
                   "Charge 15 min", "Carga 15 min", "Carga 15 min", "Нагрузка 15 мин"])
    }

    static var valDown: String {
        L10n.pick(["Download", "下载", "下載", "다운로드", "Download",
                   "Téléchargement", "Descarga", "Download", "Загрузка"])
    }

    static var valUp: String {
        L10n.pick(["Upload", "上传", "上傳", "업로드", "Upload",
                   "Envoi", "Subida", "Upload", "Отдача"])
    }

    static var valPercent: String {
        L10n.pick(["Percent", "百分比", "百分比", "백분율", "Prozent",
                   "Pourcentage", "Porcentaje", "Percentagem", "Процент"])
    }

    static var valRemaining: String {
        L10n.pick(["Time left", "剩余时间", "剩餘時間", "남은 시간", "Restzeit",
                   "Temps restant", "Tiempo restante", "Tempo restante", "Осталось"])
    }

    static var valRPM: String {
        L10n.pick(["RPM", "转速", "轉速", "RPM", "Drehzahl",
                   "Tr/min", "RPM", "RPM", "Обороты"])
    }

    static var showIcon: String {
        L10n.pick(["Icon", "显示图标", "顯示圖示", "아이콘", "Symbol",
                   "Icône", "Icono", "Ícone", "Значок"])
    }

    static var showText: String {
        L10n.pick(["Text", "显示文字", "顯示文字", "텍스트", "Text",
                   "Texte", "Texto", "Texto", "Текст"])
    }

    static var showChart: String {
        L10n.pick(["Chart", "显示图表", "顯示圖表", "차트", "Diagramm",
                   "Graphique", "Gráfico", "Gráfico", "График"])
    }

    // MARK: 面板卡片用词

    static var pnlSystem: String {
        L10n.pick(["System", "系统", "系統", "시스템", "System",
                   "Système", "Sistema", "Sistema", "Система"])
    }

    static var pnlUser: String {
        L10n.pick(["User", "用户", "使用者", "사용자", "Benutzer",
                   "Utilisateur", "Usuario", "Utilizador", "Пользователь"])
    }

    static var pnlCached: String {
        L10n.pick(["Cached", "已缓存", "已快取", "캐시됨", "Cache",
                   "Cache", "Caché", "Cache", "Кэш"])
    }

    static var pnlApp: String {
        L10n.pick(["App", "App", "App", "앱", "App",
                   "App", "App", "App", "App"])
    }

    static var pnlWired: String {
        L10n.pick(["Wired", "联动", "聯動", "고정", "Verdrahtet",
                   "Câblé", "Cableado", "Cablado", "Связано"])
    }

    static var pnlCompressed: String {
        L10n.pick(["Compressed", "被压缩", "被壓縮", "압축됨", "Komprimiert",
                   "Compressé", "Comprimido", "Comprimido", "Сжато"])
    }

    static var pnlPower: String {
        L10n.pick(["Power", "电源", "電源", "전원", "Strom",
                   "Alim.", "Energía", "Energia", "Питание"])
    }

    static var pnlCharging: String {
        L10n.pick(["Charging", "充电中", "充電中", "충전 중", "Lädt",
                   "En charge", "Cargando", "A carregar", "Зарядка"])
    }

    static var pnlCycles: String {
        L10n.pick(["Cycles", "循环", "循環", "사이클", "Zyklen",
                   "Cycles", "Ciclos", "Ciclos", "Циклы"])
    }

    static var pnlAdapter: String {
        L10n.pick(["Adapter", "电源适配器", "電源轉接器", "어댑터", "Netzteil",
                   "Adaptateur", "Adaptador", "Adaptador", "Адаптер"])
    }

    static var pnlBattery: String {
        L10n.pick(["Battery", "电池", "電池", "배터리", "Akku",
                   "Batterie", "Batería", "Bateria", "Батарея"])
    }

    static var pnlYes: String {
        L10n.pick(["Yes", "是", "是", "예", "Ja", "Oui", "Sí", "Sim", "Да"])
    }

    static var pnlNo: String {
        L10n.pick(["No", "否", "否", "아니오", "Nein", "Non", "No", "Não", "Нет"])
    }

    static var noteNoCapacity: String {
        L10n.pick(["This Mac does not expose design/full capacity in mAh.",
                   "本机不提供电池的设计容量 / mAh 数据（系统只给百分比）。",
                   "本機不提供電池的設計容量 / mAh 資料（系統只給百分比）。",
                   "이 Mac은 배터리 설계 용량/mAh 정보를 제공하지 않습니다.",
                   "Dieser Mac liefert keine Design-/Vollkapazität in mAh.",
                   "Ce Mac ne fournit pas la capacité de conception en mAh.",
                   "Este Mac no ofrece la capacidad de diseño en mAh.",
                   "Este Mac não fornece a capacidade de projeto em mAh.",
                   "Этот Mac не сообщает проектную ёмкость в mAh."])
    }

    static var pnlCondition: String {
        L10n.pick(["Condition", "状况", "狀況", "상태", "Zustand",
                   "État", "Estado", "Estado", "Состояние"])
    }

    static var pnlGood: String {
        L10n.pick(["Good", "好", "良好", "좋음", "Gut", "Bon", "Buena", "Bom", "Хорошо"])
    }

    static var pnlFair: String {
        L10n.pick(["Fair", "一般", "一般", "보통", "Mittel", "Moyen", "Regular", "Razoável", "Средне"])
    }

    static var pnlPoor: String {
        L10n.pick(["Poor", "较差", "較差", "나쁨", "Schlecht", "Faible", "Mala", "Má", "Плохо"])
    }

    static var pnlHealth: String {
        L10n.pick(["Health", "健康度", "健康度", "배터리 건강", "Zustand",
                   "Santé", "Salud", "Saúde", "Износ"])
    }

    static var pnlDesign: String {
        L10n.pick(["Design", "设计容量", "設計容量", "설계 용량", "Design",
                   "Conception", "Diseño", "Design", "Проектная"])
    }

    static var pnlReal: String {
        L10n.pick(["Full charge", "真实容量", "真實容量", "실제 용량", "Vollstand",
                   "Charge réelle", "Carga real", "Carga real", "Фактическая"])
    }

    static var pnlFan: String {
        L10n.pick(["Fan", "风扇", "風扇", "팬", "Lüfter",
                   "Ventilateur", "Ventilador", "Ventoinha", "Вентилятор"])
    }

    static var secComponents: String {
        L10n.pick(["Status items", "组件显示", "元件顯示", "항목 표시", "Statusobjekte",
                   "Éléments affichés", "Elementos mostrados", "Itens exibidos", "Элементы"])
    }

    static var noteComponentDetail: String {
        L10n.pick(["Pick a component on the left, then choose what it shows in the band.",
                   "左侧选择组件，右侧设置它在带子里显示什么。",
                   "左側選擇元件，右側設定它在帶子裡顯示什麼。",
                   "왼쪽에서 항목을 고르고, 오른쪽에서 밴드에 표시할 내용을 설정하세요.",
                   "Links ein Element wählen, rechts einstellen, was es im Band zeigt.",
                   "Choisissez un élément à gauche, réglez son affichage à droite.",
                   "Elige un elemento a la izquierda y ajusta qué muestra a la derecha.",
                   "Escolha um item à esquerda e ajuste o que ele mostra à direita.",
                   "Выберите элемент слева и настройте его отображение справа."])
    }

    static var noteAvailable: String {
        L10n.pick(["Available — click to add", "可用 · 点选添加", "可用 · 點選新增",
                   "사용 가능 · 클릭해 추가", "Verfügbar — klicken zum Hinzufügen",
                   "Disponible — cliquer pour ajouter", "Disponible — clic para añadir",
                   "Disponível — clique para adicionar", "Доступно — нажмите, чтобы добавить"])
    }

    static var metricDetail: String {
        L10n.pick(["Editing", "正在编辑", "正在編輯", "편집 중", "Bearbeiten",
                   "Édition", "Editando", "Editando", "Правка"])
    }

    static var noteValues: String {
        L10n.pick(["Click to add, drag to reorder. Up to 2 show in the band.",
                   "点选添加、拖动排序；带子里最多显示 2 项。",
                   "點選新增、拖曳排序；帶子裡最多顯示 2 項。",
                   "클릭해 추가, 드래그해 정렬. 밴드에는 최대 2개까지 표시.",
                   "Klicken zum Hinzufügen, ziehen zum Sortieren. Max. 2 im Band.",
                   "Cliquer pour ajouter, glisser pour trier. 2 max dans le bandeau.",
                   "Clic para añadir, arrastra para ordenar. Máx. 2 en la banda.",
                   "Clique para adicionar, arraste para ordenar. Máx. 2 na faixa.",
                   "Нажмите, чтобы добавить, перетащите для порядка. В полосе до 2."])
    }

    static var noteMaxLines: String {
        L10n.pick(["Only the first 2 values are shown in the band.",
                   "带子里只显示前 2 项，多出的会被忽略。",
                   "帶子裡只顯示前 2 項，多出的會被忽略。",
                   "밴드에는 처음 2개만 표시됩니다.",
                   "Im Band werden nur die ersten 2 Werte angezeigt.",
                   "Seules les 2 premières valeurs sont affichées.",
                   "Solo se muestran los 2 primeros valores.",
                   "Apenas os 2 primeiros valores são exibidos.",
                   "В полосе показываются только первые 2 значения."])
    }

    static var showValues: String {
        L10n.pick(["Show values", "显示数值", "顯示數值", "값 표시", "Werte anzeigen",
                   "Afficher les valeurs", "Mostrar valores", "Mostrar valores", "Показывать значения"])
    }

    static var noteMetrics: String {
        L10n.pick(["Pick what the 310 px band shows. The order below is the display order.",
                   "选择 310px 带子里显示哪些组件，顺序与下面一致。",
                   "選擇 310px 帶子裡顯示哪些元件，順序與下面一致。",
                   "310px 밴드에 표시할 항목을 선택하세요. 아래 순서대로 표시됩니다.",
                   "Wähle, was das 310-px-Band zeigt. Die Reihenfolge unten ist die Anzeigereihenfolge.",
                   "Choisissez ce que le bandeau de 310 px affiche. L'ordre ci-dessous est celui de l'affichage.",
                   "Elige qué muestra la banda de 310 px. El orden de abajo es el de visualización.",
                   "Escolha o que a faixa de 310 px mostra. A ordem abaixo é a de exibição.",
                   "Выберите, что показывать в полосе 310 px. Порядок ниже — порядок вывода."])
    }

    static var noteNet: String {
        L10n.pick(["The icon follows the active interface: Wi-Fi, wired, or cellular (phone hotspot / USB tethering counts as cellular). 5G/4G is estimated from the peak rate of the last minute.",
                   "网络图标跟随当前接口：Wi-Fi / 有线 / 蜂窝。手机热点、USB 共享会显示为蜂窝；5G/4G 按最近一分钟的峰值速率估算。",
                   "網路圖示跟隨目前介面：Wi-Fi / 有線 / 行動網路。手機熱點、USB 共享會顯示為行動網路；5G/4G 依最近一分鐘的峰值速率估算。",
                   "아이콘은 현재 인터페이스를 따릅니다: Wi-Fi / 유선 / 셀룰러(휴대폰 핫스팟·USB 테더링 포함). 5G/4G는 최근 1분 최고 속도로 추정합니다.",
                   "Das Symbol folgt der aktiven Schnittstelle: WLAN, LAN oder Mobilfunk (Hotspot/USB-Tethering zählt als Mobilfunk). 5G/4G wird aus der Spitzengeschwindigkeit der letzten Minute geschätzt.",
                   "L'icône suit l'interface active : Wi-Fi, filaire ou cellulaire (partage de connexion du téléphone compté comme cellulaire). 5G/4G est estimé d'après le débit maximal de la dernière minute.",
                   "El icono sigue la interfaz activa: Wi-Fi, cable o móvil (un hotspot del teléfono cuenta como móvil). 5G/4G se estima con la velocidad máxima del último minuto.",
                   "O ícone segue a interface ativa: Wi-Fi, cabo ou celular (hotspot do telefone conta como celular). 5G/4G é estimado pela velocidade máxima do último minuto.",
                   "Значок следует активному интерфейсу: Wi-Fi, кабель или сотовая сеть (раздача с телефона считается сотовой). 5G/4G оцениваются по пиковой скорости за последнюю минуту."])
    }

    static var noteFan: String {
        L10n.pick(["Fan speed has no public API: it is read through SMC. When it cannot be read, the item is shown as disabled here and hidden from the band.",
                   "风扇转速没有公开 API，通过 SMC 读取；读不到时这里显示为禁用，带子里也不显示。",
                   "風扇轉速沒有公開 API，透過 SMC 讀取；讀不到時這裡顯示為停用，帶子裡也不顯示。",
                   "팬 속도는 공개 API가 없어 SMC로 읽습니다. 읽을 수 없으면 여기서 사용 안 함으로 표시되고 밴드에도 나오지 않습니다.",
                   "Für die Lüfterdrehzahl gibt es keine öffentliche API; sie wird über SMC gelesen. Ist sie nicht lesbar, erscheint der Eintrag hier deaktiviert und im Band nicht.",
                   "La vitesse du ventilateur n'a pas d'API publique : lecture via SMC. Si elle est illisible, l'élément apparaît désactivé ici et masqué dans le bandeau.",
                   "La velocidad del ventilador no tiene API pública: se lee por SMC. Si no se puede leer, aquí aparece desactivado y no se muestra en la banda.",
                   "A velocidade da ventoinha não tem API pública: é lida via SMC. Se não for possível, aqui aparece desativado e não é exibido na faixa.",
                   "У скорости вентилятора нет публичного API: читается через SMC. Если недоступна — здесь показано «отключено», в полосе не отображается."])
    }

    static var navPanel: String {
        L10n.pick(["Status Panel", "状态面板", "狀態面板", "상태 패널", "Statuspanel",
                   "Panneau d'état", "Panel de estado", "Painel de estado", "Панель состояния"])
    }

    static var navAbout: String {
        L10n.pick(["About", "关于", "關於", "정보", "Info", "À propos", "Acerca de", "Sobre", "О программе"])
    }

    // MARK: 通用

    static var secStartup: String {
        L10n.pick(["Startup", "启动", "啟動", "시작", "Start", "Démarrage", "Inicio", "Início", "Запуск"])
    }

    static var launchAtLogin: String {
        L10n.pick(["Launch at login", "开机自启动", "開機時自動啟動", "로그인 시 실행",
                   "Beim Anmelden öffnen", "Ouvrir à la connexion", "Abrir al iniciar sesión",
                   "Abrir ao iniciar sessão", "Запускать при входе"])
    }

    // MARK: 权限（未授权时才显示）

    static var secPermission: String {
        L10n.pick(["Permissions", "权限", "權限", "권한", "Berechtigungen",
                   "Autorisations", "Permisos", "Permissões", "Разрешения"])
    }

    static var permAccessibility: String {
        L10n.pick(["Accessibility", "辅助功能", "輔助使用", "손쉬운 사용", "Bedienungshilfen",
                   "Accessibilité", "Accesibilidad", "Acessibilidade", "Универсальный доступ"])
    }

    static var permGrant: String {
        L10n.pick(["Open Settings", "去授权", "前往授權", "설정 열기", "Einstellungen öffnen",
                   "Ouvrir les réglages", "Abrir Ajustes", "Abrir Ajustes", "Открыть настройки"])
    }

    static var permAccessibilityNote: String {
        L10n.pick(["Only needed to read and click other apps' menu bar icons. Status items and the panel work without it.",
                   "仅用于读取和点击其它应用的菜单栏图标；状态栏带子与面板不需要它也能正常工作。",
                   "僅用於讀取和點擊其他應用程式的選單列圖示；狀態列與面板不需要它也能正常運作。",
                   "다른 앱의 메뉴 막대 아이콘을 읽고 클릭할 때만 필요합니다. 상태 막대와 패널은 없어도 동작합니다.",
                   "Wird nur zum Lesen und Anklicken fremder Menüleisten-Symbole benötigt. Statusleiste und Panel funktionieren auch ohne.",
                   "Nécessaire uniquement pour lire et cliquer les icônes des autres apps. La barre et le panneau fonctionnent sans.",
                   "Solo se necesita para leer y pulsar iconos de otras apps. La barra y el panel funcionan sin ello.",
                   "Só é necessário para ler e clicar ícones de outras apps. A barra e o painel funcionam sem isso.",
                   "Нужен только для чтения и нажатия значков других приложений. Строка и панель работают и без него."])
    }

    static var secLanguage: String {
        L10n.pick(["Language", "语言", "語言", "언어", "Sprache", "Langue", "Idioma", "Idioma", "Язык"])
    }

    static var languageRow: String {
        L10n.pick(["Language", "语言选择", "語言選擇", "언어 선택", "Sprache", "Langue",
                   "Idioma", "Idioma", "Язык интерфейса"])
    }

    static var secWindow: String {
        L10n.pick(["Window", "窗口", "視窗", "윈도우", "Fenster", "Fenêtre", "Ventana", "Janela", "Окно"])
    }

    static var closeAction: String {
        L10n.pick(["When closing", "关闭时操作", "關閉時動作", "닫을 때", "Beim Schließen",
                   "À la fermeture", "Al cerrar", "Ao fechar", "При закрытии"])
    }

    static var closeMinimize: String {
        L10n.pick(["Minimize", "最小化", "最小化", "최소화", "Minimieren", "Réduire",
                   "Minimizar", "Minimizar", "Свернуть"])
    }

    static var closeQuit: String {
        L10n.pick(["Quit", "退出", "結束", "종료", "Beenden", "Quitter", "Salir", "Sair", "Выйти"])
    }

    static var noteInstant: String {
        L10n.pick(["Changes take effect immediately; there is no OK button.",
                   "修改立即生效，不需要确定按钮。", "修改立即生效，不需確定按鈕。",
                   "변경 사항은 즉시 적용되며 확인 버튼이 없습니다.",
                   "Änderungen wirken sofort, es gibt keinen OK-Button.",
                   "Les modifications s'appliquent immédiatement, sans bouton OK.",
                   "Los cambios se aplican al instante, sin botón Aceptar.",
                   "As alterações aplicam-se de imediato, sem botão OK.",
                   "Изменения применяются сразу, кнопки OK нет."])
    }

    // MARK: 菜单栏

    static var secCollect: String {
        L10n.pick(["Collection", "收纳", "收納", "수집", "Sammlung", "Rangement", "Recogida", "Recolha", "Сбор"])
    }

    static var mode: String {
        L10n.pick(["Mode", "模式", "模式", "모드", "Modus", "Mode", "Modo", "Modo", "Режим"])
    }

    static var modeFill: String {
        L10n.pick(["Take everything", "撑满收纳", "撐滿收納", "최대 채우기", "Alles aufnehmen",
                   "Tout replier", "Ocupar todo", "Ocupar tudo", "Забрать всё"])
    }

    static var modeKeep: String {
        L10n.pick(["Keep a set number", "保留指定数量", "保留指定數量", "지정 개수 유지",
                   "Feste Anzahl", "Garder N icônes", "Conservar N iconos", "Manter N ícones",
                   "Оставить N значков"])
    }

    static var openLog: String {
        L10n.pick(["Open log", "打开日志", "開啟日誌", "로그 열기", "Protokoll öffnen",
                   "Ouvrir le journal", "Abrir registro", "Abrir registo", "Открыть журнал"])
    }

    // MARK: 应用

    static var secAppsList: String {
        L10n.pick(["Show & order", "显示与顺序", "顯示與順序", "표시 및 순서", "Anzeige & Reihenfolge",
                   "Affichage et ordre", "Mostrar y ordenar", "Mostrar e ordenar", "Показ и порядок"])
    }

    static var noteApps: String {
        L10n.pick(["Checked icons stay in the menu bar; reorder with ↑ ↓ and it is remembered.",
                   "勾选 = 图标留在菜单栏；顺序用 ↑ ↓ 调整，会记住。",
                   "勾選 = 圖示留在選單列；順序用 ↑ ↓ 調整並記住。",
                   "체크 = 메뉴 막대에 유지, 순서는 ↑ ↓ 로 조정되며 기억됩니다.",
                   "Haken = Symbol bleibt in der Menüleiste; Reihenfolge mit ↑ ↓, wird gemerkt.",
                   "Coché = l'icône reste dans la barre des menus ; ordre via ↑ ↓, mémorisé.",
                   "Marcado = el icono se queda en la barra; orden con ↑ ↓, se recuerda.",
                   "Marcado = o ícone fica na barra; ordem com ↑ ↓, é memorizada.",
                   "Галочка = значок остаётся в строке меню; порядок стрелками ↑ ↓, запоминается."])
    }

    static var noteNoPinned: String {
        L10n.pick(["No app checked yet (take-everything folds them all).",
                   "当前没有勾选的 App（撑满收纳时全部折叠）。",
                   "目前沒有勾選的 App（撐滿收納時全部折疊）。",
                   "선택된 앱이 없습니다(최대 채우기 시 모두 접힘).",
                   "Keine App gewählt (alles aufnehmen faltet alle).",
                   "Aucune app cochée (tout replier les replie toutes).",
                   "Ninguna app marcada (ocupar todo las pliega).",
                   "Nenhuma app marcada (ocupar tudo dobra todas).",
                   "Ни одно приложение не выбрано (при «забрать всё» все складываются)."])
    }

    static var unpinnedHeader: String {
        L10n.pick(["Unchecked (folded into <<)", "未勾选（会被折进 <<）", "未勾選（會被折進 <<）",
                   "미선택(<< 로 접힘)", "Nicht gewählt (in << gefaltet)",
                   "Non cochées (repliées dans <<)", "Sin marcar (se pliegan en <<)",
                   "Não marcadas (dobradas em <<)", "Без галочки (уйдут в <<)"])
    }

    // MARK: 面板

    static var secAppearance: String {
        L10n.pick(["Appearance", "外观", "外觀", "모양", "Darstellung", "Apparence",
                   "Apariencia", "Aparência", "Оформление"])
    }

    static var background: String {
        L10n.pick(["Background", "背景", "背景", "배경", "Hintergrund", "Fond", "Fondo", "Fundo", "Фон"])
    }

    static var bgBlur: String {
        L10n.pick(["System blur (release)", "系统毛玻璃（正式）", "系統毛玻璃（正式）",
                   "시스템 블러(정식)", "System-Blur (Release)", "Flou système (final)",
                   "Desenfoque del sistema (final)", "Desfoque do sistema (final)",
                   "Системное размытие (релиз)"])
    }

    static var bgWhite: String {
        L10n.pick(["Plain white (testing)", "纯白（测试）", "純白（測試）", "순백(테스트)",
                   "Reinweiß (Test)", "Blanc pur (test)", "Blanco puro (prueba)",
                   "Branco puro (teste)", "Чистый белый (тест)"])
    }

    static var sortOrder: String {
        L10n.pick(["List order", "列表排序", "列表排序", "목록 정렬", "Listenreihenfolge",
                   "Ordre de la liste", "Orden de la lista", "Ordem da lista", "Сортировка списка"])
    }

    static var sortByName: String {
        L10n.pick(["By name", "按名称", "按名稱", "이름순", "Nach Name", "Par nom",
                   "Por nombre", "Por nome", "По имени"])
    }

    static var sortByPosition: String {
        L10n.pick(["By menu bar position", "按菜单栏位置", "按選單列位置", "메뉴 막대 위치순",
                   "Nach Menüleistenposition", "Par position dans la barre", "Por posición en la barra",
                   "Por posição na barra", "По позиции в строке меню"])
    }

    static var showStats: String {
        L10n.pick(["Show the “Menu bar” stats card", "显示「菜单栏」统计卡片", "顯示「選單列」統計卡片",
                   "“메뉴 막대” 통계 카드 표시", "„Menüleiste“-Statistik anzeigen",
                   "Afficher la carte « Barre des menus »", "Mostrar tarjeta «Barra de menús»",
                   "Mostrar cartão «Barra de menus»", "Показывать карточку «Строка меню»"])
    }

    static var secList: String {
        L10n.pick(["List", "列表", "列表", "목록", "Liste", "Liste", "Lista", "Lista", "Список"])
    }

    static var visibleRows: String {
        L10n.pick(["Visible rows", "可见行数", "可見列數", "표시 행 수", "Sichtbare Zeilen",
                   "Lignes visibles", "Filas visibles", "Linhas visíveis", "Видимых строк"])
    }

    static var panelWidth: String {
        L10n.pick(["Panel width", "面板宽度", "面板寬度", "패널 너비", "Panelbreite",
                   "Largeur du panneau", "Ancho del panel", "Largura do painel", "Ширина панели"])
    }

    /// 数字框后面的单位
    static var unitItems: String {
        L10n.pick(["items", "项", "項", "개", "Einträge", "éléments", "elementos", "itens", "шт."])
    }

    static var unitRows: String {
        L10n.pick(["rows", "行", "列", "행", "Zeilen", "lignes", "filas", "linhas", "строк"])
    }

    static var notePanel: String {
        L10n.pick(["Panel width and content layout will keep evolving.",
                   "面板宽度与内容显示逻辑后续继续完善。",
                   "面板寬度與內容顯示邏輯後續繼續完善。",
                   "패널 너비와 내용 표시는 계속 다듬을 예정입니다.",
                   "Panelbreite und Inhaltsanzeige werden weiter verfeinert.",
                   "La largeur et l'affichage du panneau seront encore affinés.",
                   "El ancho y la visualización del panel seguirán mejorando.",
                   "A largura e a apresentação do painel vão continuar a ser afinadas.",
                   "Ширина панели и показ содержимого будут дорабатываться."])
    }

    // MARK: 关于

    static var configFile: String {
        L10n.pick(["Config file", "配置文件", "設定檔", "설정 파일", "Konfigurationsdatei",
                   "Fichier de config", "Archivo de configuración", "Ficheiro de configuração",
                   "Файл конфигурации"])
    }

    static var runLog: String {
        L10n.pick(["Runtime log", "运行日志", "執行日誌", "실행 로그", "Laufzeitprotokoll",
                   "Journal d'exécution", "Registro de ejecución", "Registo de execução",
                   "Журнал работы"])
    }

    static var docs: String {
        L10n.pick(["Docs", "文档", "文件", "문서", "Dokumente", "Documentation",
                   "Documentación", "Documentação", "Документация"])
    }

    static var open: String {
        L10n.pick(["Open", "打开", "開啟", "열기", "Öffnen", "Ouvrir", "Abrir", "Abrir", "Открыть"])
    }

    static var quitApp: String {
        L10n.pick(["Quit StatusX", "退出 StatusX", "結束 StatusX", "StatusX 종료",
                   "StatusX beenden", "Quitter StatusX", "Salir de StatusX", "Sair do StatusX",
                   "Выйти из StatusX"])
    }

    static func buildTag(_ build: String) -> String {
        String(format: L10n.pick(["build %@", "构建 %@", "建置 %@", "빌드 %@", "Build %@",
                                  "build %@", "compilación %@", "compilação %@", "сборка %@"]), build)
    }

    // MARK: 面板（弹出窗）用到的文案

    static var prefs: String {
        L10n.pick(["Preferences", "偏好设置", "偏好設定", "환경설정", "Einstellungen",
                   "Préférences", "Preferencias", "Preferências", "Настройки"])
    }

    static var menuBarCard: String {
        L10n.pick(["Menu bar", "菜单栏", "選單列", "메뉴 막대", "Menüleiste",
                   "Barre des menus", "Barra de menús", "Barra de menus", "Строка меню"])
    }

    static var folded: String {
        L10n.pick(["Folded", "折叠", "摺疊", "접힘", "Gefaltet", "Repliés",
                   "Plegados", "Dobrados", "Скрыто"])
    }

    static var kept: String {
        L10n.pick(["Kept", "保留", "保留", "유지", "Behalten", "Gardés",
                   "Conservados", "Mantidos", "Оставлено"])
    }

    static var total: String {
        L10n.pick(["Total", "合计", "合計", "합계", "Gesamt", "Total", "Total", "Total", "Всего"])
    }

    static var foldedSection: String {
        L10n.pick(["Folded", "已折叠", "已摺疊", "접힌 항목", "Gefaltet", "Repliés",
                   "Plegados", "Dobrados", "Скрытые"])
    }

    /// 面板里出现的 “N 项 / N items”
    static func itemCount(_ n: Int) -> String {
        String(format: L10n.pick(["%d items", "%d 项", "%d 項", "%d개", "%d Einträge",
                                  "%d éléments", "%d elementos", "%d itens", "%d шт."]), n)
    }

    /// 列表底部 “滚动查看其余 N 项”
    static func scrollMore(_ n: Int) -> String {
        String(format: L10n.pick(["Scroll for %d more", "滚动查看其余 %d 项", "捲動查看其餘 %d 項",
                                  "%d개 더 보기", "%d weitere scrollen", "%d de plus à faire défiler",
                                  "Desplázate para ver %d más", "Deslize para ver mais %d",
                                  "Прокрутите, чтобы увидеть ещё %d"]), n)
    }
}
