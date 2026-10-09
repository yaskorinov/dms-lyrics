import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "wordLyrics"

    SelectionSetting {
        settingKey: "textAlign"
        label: "Выравнивание текста"
        description: "Строки, перенос, точки паузы и надписи состояния"
        options: [
            { label: "По левому краю (как Apple Music)", value: "left" },
            { label: "По центру", value: "center" },
            { label: "По правому краю", value: "right" }
        ]
        defaultValue: "left"
    }

    SliderSetting {
        settingKey: "fontSize"
        label: "Размер шрифта"
        defaultValue: 34
        minimum: 14
        maximum: 80
        unit: "px"
    }

    StringSetting {
        settingKey: "fontFamily"
        label: "Шрифт"
        description: "Пусто — шрифт темы DMS"
        placeholder: "SF Pro Display"
        defaultValue: ""
    }

    SelectionSetting {
        settingKey: "anchorPos"
        label: "Положение активной строки"
        options: [
            { label: "Верхняя треть", value: "0.33" },
            { label: "Центр", value: "0.5" },
            { label: "Сверху", value: "0.2" }
        ]
        defaultValue: "0.33"
    }

    SelectionSetting {
        settingKey: "colorMode"
        label: "Цвет текста"
        options: [
            { label: "Белый", value: "white" },
            { label: "Акцент темы", value: "primary" },
            { label: "Текст темы", value: "surface" }
        ]
        defaultValue: "white"
    }

    SliderSetting {
        settingKey: "dimOpacity"
        label: "Яркость неактивного текста"
        defaultValue: 35
        minimum: 10
        maximum: 80
        unit: "%"
    }

    ToggleSetting {
        settingKey: "blurInactive"
        label: "Размывать неактивные строки"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "textShadow"
        label: "Тень под текстом"
        description: "Читаемость на светлых обоях"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "edgeFade"
        label: "Затухание по краям"
        description: "Текст плавно уходит в прозрачность у верхнего и нижнего края"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "fadeTop"
        label: "Высота затухания сверху"
        description: "Доля высоты виджета; не заходит на активную строку"
        defaultValue: 30
        minimum: 0
        maximum: 60
        unit: "%"
    }

    SliderSetting {
        settingKey: "fadeBottom"
        label: "Высота затухания снизу"
        defaultValue: 18
        minimum: 0
        maximum: 60
        unit: "%"
    }

    SelectionSetting {
        settingKey: "scrollCurve"
        label: "Кривая прокрутки"
        options: [
            { label: "Ease in-out (кубическая)", value: "easeInOut" },
            { label: "Мягкая (синусоида)", value: "sine" },
            { label: "Выразительная (quart in-out)", value: "expressive" },
            { label: "Apple ease-in-out (bezier)", value: "apple" },
            { label: "Пружина (с лёгким перелётом)", value: "spring" }
        ]
        defaultValue: "easeInOut"
    }

    SliderSetting {
        settingKey: "scrollDuration"
        label: "Длительность прокрутки"
        defaultValue: 700
        minimum: 250
        maximum: 1600
        unit: "ms"
    }

    SliderSetting {
        settingKey: "scrollStagger"
        label: "Волна между строками"
        description: "Задержка каждой следующей строки; 0 — весь текст едет одним блоком"
        defaultValue: 45
        minimum: 0
        maximum: 100
        unit: "ms"
    }

    SliderSetting {
        settingKey: "scrollLead"
        label: "Опережение прокрутки"
        description: "Строка начинает ехать раньше, чем её поют: подсветка стартует, пока анимация ещё идёт"
        defaultValue: 250
        minimum: 0
        maximum: 1000
        unit: "ms"
    }

    SliderSetting {
        settingKey: "offsetMs"
        label: "Сдвиг синхронизации"
        description: "Плюс — текст раньше, минус — позже"
        defaultValue: 0
        minimum: -2000
        maximum: 2000
        unit: "ms"
    }

    ToggleSetting {
        settingKey: "hideWhenPaused"
        label: "Скрывать на паузе"
        defaultValue: false
    }

    StringSetting {
        settingKey: "preferredPlayer"
        label: "Предпочитаемый плеер"
        description: "Часть имени MPRIS-плеера (например cassette). Пусто — активный плеер DMS"
        placeholder: "cassette"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "musixmatchToken"
        label: "Musixmatch usertoken"
        description: "Необязательно. Без него берётся анонимный токен (из некоторых сетей не выдаётся)"
        defaultValue: ""
    }
}
