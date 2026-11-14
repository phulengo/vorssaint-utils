// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarAppearanceStrings {
    let label: String
    let values: String
    let bars: String
    let rings: String
    let caption: String
    let customize: String
    /// A reading's own style, in its options.
    let style: String
    /// The style choice that keeps a reading on the Usage display choice.
    let sameAsUsageDisplay: String
    let normalColor: String
    let mediumColor: String
    let highColor: String
    let mediumFrom: String
    let highFrom: String

    func title(_ appearance: MenuBarMetricAppearance) -> String {
        switch appearance {
        case .values: return values
        case .bars: return bars
        case .ring: return rings
        }
    }
}

extension FeatureStrings {
    static func menuBarAppearance(_ language: AppLanguage) -> MenuBarAppearanceStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension MenuBarAppearanceStrings {
    static let enUS = MenuBarAppearanceStrings(
        label: "Usage display",
        values: "Values",
        bars: "Bars",
        rings: "Rings",
        caption: "Bars and rings apply to CPU, GPU, memory, disk usage and AI Agents. Any of these, battery included, can keep a style of its own in its options. Other readings stay numeric.",
        customize: "Gauge colors and limits",
        style: "Style",
        sameAsUsageDisplay: "Same as Usage display",
        normalColor: "Normal color",
        mediumColor: "Medium color",
        highColor: "High color",
        mediumFrom: "Medium from",
        highFrom: "High from"
    )

    static let ptBR = MenuBarAppearanceStrings(
        label: "Exibição de uso",
        values: "Valores",
        bars: "Barras",
        rings: "Anéis",
        caption: "Barras e anéis valem para CPU, GPU, memória, uso de disco e Agentes de IA. Qualquer um deles, inclusive a bateria, pode ter o próprio estilo nas opções. As outras leituras continuam numéricas.",
        customize: "Cores e limites dos medidores",
        style: "Estilo",
        sameAsUsageDisplay: "Igual à Exibição de uso",
        normalColor: "Cor normal",
        mediumColor: "Cor média",
        highColor: "Cor alta",
        mediumFrom: "Médio a partir de",
        highFrom: "Alto a partir de"
    )

    static let tr = MenuBarAppearanceStrings(
        label: "Kullanım görünümü",
        values: "Değerler",
        bars: "Çubuklar",
        rings: "Halkalar",
        caption: "Çubuklar ve halkalar CPU, GPU, bellek, disk kullanımı ve YZ Ajanları için geçerlidir. Pil dahil bunların her biri, seçeneklerinde kendi stilini alabilir. Diğer ölçümler sayısal kalır.",
        customize: "Gösterge renkleri ve sınırları",
        style: "Stil",
        sameAsUsageDisplay: "Kullanım görünümüyle aynı",
        normalColor: "Normal renk",
        mediumColor: "Orta renk",
        highColor: "Yüksek renk",
        mediumFrom: "Orta başlangıcı",
        highFrom: "Yüksek başlangıcı"
    )

    static let ru = MenuBarAppearanceStrings(
        label: "Отображение нагрузки",
        values: "Значения",
        bars: "Шкалы",
        rings: "Кольца",
        caption: "Шкалы и кольца применяются к CPU, GPU, памяти, занятости диска и ИИ-агентам. Любому из них, включая аккумулятор, можно задать свой стиль в его параметрах. Остальные показатели остаются числовыми.",
        customize: "Цвета и пороги индикаторов",
        style: "Стиль",
        sameAsUsageDisplay: "Как в отображении нагрузки",
        normalColor: "Обычный цвет",
        mediumColor: "Средний цвет",
        highColor: "Высокий цвет",
        mediumFrom: "Средний от",
        highFrom: "Высокий от"
    )

    static let es = MenuBarAppearanceStrings(
        label: "Vista de uso",
        values: "Valores",
        bars: "Barras",
        rings: "Anillos",
        caption: "Las barras y los anillos se aplican a CPU, GPU, memoria, uso de disco y Agentes de IA. Cualquiera de ellos, incluida la batería, puede tener su propio estilo en sus opciones. Las demás lecturas siguen siendo numéricas.",
        customize: "Colores y límites de los indicadores",
        style: "Estilo",
        sameAsUsageDisplay: "Igual que la Vista de uso",
        normalColor: "Color normal",
        mediumColor: "Color medio",
        highColor: "Color alto",
        mediumFrom: "Medio desde",
        highFrom: "Alto desde"
    )

    static let sk = MenuBarAppearanceStrings(
        label: "Zobrazenie vyťaženia",
        values: "Hodnoty",
        bars: "Pruhy",
        rings: "Kruhy",
        caption: "Pruhy a kruhy platia pre CPU, GPU, pamäť, využitie disku a AI agentov. Ktorákoľvek z týchto hodnôt vrátane batérie môže mať vo svojich možnostiach vlastný štýl. Ostatné hodnoty zostávajú číselné.",
        customize: "Farby a limity ukazovateľov",
        style: "Štýl",
        sameAsUsageDisplay: "Ako zobrazenie vyťaženia",
        normalColor: "Bežná farba",
        mediumColor: "Stredná farba",
        highColor: "Vysoká farba",
        mediumFrom: "Stredná od",
        highFrom: "Vysoká od"
    )

    static let de = MenuBarAppearanceStrings(
        label: "Auslastungsanzeige",
        values: "Werte",
        bars: "Balken",
        rings: "Ringe",
        caption: "Balken und Ringe gelten für CPU, GPU, Speicher, Festplattenbelegung und KI-Agenten. Jeder davon, auch der Akku, kann in seinen Optionen einen eigenen Stil haben. Andere Messwerte bleiben numerisch.",
        customize: "Anzeigefarben und Grenzwerte",
        style: "Stil",
        sameAsUsageDisplay: "Wie Auslastungsanzeige",
        normalColor: "Normale Farbe",
        mediumColor: "Mittlere Farbe",
        highColor: "Hohe Farbe",
        mediumFrom: "Mittel ab",
        highFrom: "Hoch ab"
    )

    static let fr = MenuBarAppearanceStrings(
        label: "Affichage de l’utilisation",
        values: "Valeurs",
        bars: "Barres",
        rings: "Anneaux",
        caption: "Les barres et les anneaux s’appliquent au CPU, au GPU, à la mémoire, à l’utilisation du disque et aux Agents IA. Chacune de ces mesures, batterie comprise, peut garder son propre style dans ses options. Les autres mesures restent numériques.",
        customize: "Couleurs et seuils des jauges",
        style: "Style",
        sameAsUsageDisplay: "Comme l’affichage de l’utilisation",
        normalColor: "Couleur normale",
        mediumColor: "Couleur moyenne",
        highColor: "Couleur élevée",
        mediumFrom: "Moyen à partir de",
        highFrom: "Élevé à partir de"
    )

    static let it = MenuBarAppearanceStrings(
        label: "Visualizzazione utilizzo",
        values: "Valori",
        bars: "Barre",
        rings: "Anelli",
        caption: "Barre e anelli valgono per CPU, GPU, memoria, utilizzo del disco e Agenti IA. Ognuna di queste letture, batteria compresa, può avere uno stile proprio nelle sue opzioni. Le altre letture restano numeriche.",
        customize: "Colori e soglie degli indicatori",
        style: "Stile",
        sameAsUsageDisplay: "Come la visualizzazione utilizzo",
        normalColor: "Colore normale",
        mediumColor: "Colore medio",
        highColor: "Colore alto",
        mediumFrom: "Medio da",
        highFrom: "Alto da"
    )

    static let ja = MenuBarAppearanceStrings(
        label: "使用率の表示",
        values: "数値",
        bars: "バー",
        rings: "リング",
        caption: "バーとリングは、CPU、GPU、メモリ、ディスク使用量、AIエージェントに適用されます。バッテリーを含むこれらの項目は、それぞれのオプションで個別のスタイルを選べます。その他の測定値は数値のままです。",
        customize: "ゲージの色としきい値",
        style: "スタイル",
        sameAsUsageDisplay: "使用率の表示と同じ",
        normalColor: "通常の色",
        mediumColor: "中程度の色",
        highColor: "高負荷の色",
        mediumFrom: "中程度の開始",
        highFrom: "高負荷の開始"
    )

    static let ko = MenuBarAppearanceStrings(
        label: "사용량 표시",
        values: "값",
        bars: "막대",
        rings: "링",
        caption: "막대와 링은 CPU, GPU, 메모리, 디스크 사용량 및 AI 에이전트에 적용됩니다. 배터리를 포함한 이 항목들은 각자의 옵션에서 고유한 스타일을 지정할 수 있습니다. 다른 측정값은 숫자로 유지됩니다.",
        customize: "게이지 색상 및 기준",
        style: "스타일",
        sameAsUsageDisplay: "사용량 표시와 동일",
        normalColor: "보통 색상",
        mediumColor: "중간 색상",
        highColor: "높음 색상",
        mediumFrom: "중간 시작",
        highFrom: "높음 시작"
    )

    static let zhHans = MenuBarAppearanceStrings(
        label: "使用率显示",
        values: "数值",
        bars: "条形",
        rings: "圆环",
        caption: "条形和圆环适用于 CPU、GPU、内存、磁盘使用率和 AI 智能体。这些读数（包括电池）都可以在各自的选项中使用自己的样式。其他读数保持数字显示。",
        customize: "仪表颜色和阈值",
        style: "样式",
        sameAsUsageDisplay: "与使用率显示相同",
        normalColor: "正常颜色",
        mediumColor: "中等颜色",
        highColor: "高负载颜色",
        mediumFrom: "中等起点",
        highFrom: "高负载起点"
    )

    static let zhTW = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        rings: "圓環",
        caption: "長條和圓環適用於 CPU、GPU、記憶體、磁碟使用率和 AI 代理。這些讀數（包括電池）都可在各自的選項中使用自己的樣式。其他讀數維持數字顯示。",
        customize: "量表顏色和門檻",
        style: "樣式",
        sameAsUsageDisplay: "與使用率顯示相同",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )

    static let zhHK = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        rings: "圓環",
        caption: "長條及圓環適用於 CPU、GPU、記憶體、磁碟使用率及 AI 代理。這些讀數（包括電池）都可在各自的選項中使用自己的樣式。其他讀數維持數字顯示。",
        customize: "量表顏色及門檻",
        style: "樣式",
        sameAsUsageDisplay: "與使用率顯示相同",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點"
    )
    static let uk = MenuBarAppearanceStrings(
        label: "Відображення використання",
        values: "Значення",
        bars: "Смуги",
        rings: "Кільця",
        caption: "Смуги й кільця застосовуються до CPU, GPU, пам’яті, використання диска та ШІ-агентів. Кожен із них, зокрема акумулятор, може мати власний стиль у своїх параметрах. Інші показники залишаються числовими.",
        customize: "Кольори та ліміти індикаторів",
        style: "Стиль",
        sameAsUsageDisplay: "Як у відображенні використання",
        normalColor: "Звичайний колір",
        mediumColor: "Середній колір",
        highColor: "Високий колір",
        mediumFrom: "Середній від",
        highFrom: "Високий від"
    )
}
