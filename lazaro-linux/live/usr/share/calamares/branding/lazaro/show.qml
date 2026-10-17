/* Presentación que se ve mientras se instala Lázaro Linux. */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 12000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            id: logo
            source: "bienvenida.png"
            fillMode: Image.PreserveAspectFit
            width: Math.min(parent.width * 0.9, 640)
            anchors.centerIn: parent
        }
    }
    Slide {
        centeredText: "Tu hardware aún tiene pulso.<br/><br/>Lázaro Linux le da una segunda vida a tu equipo: documentos, PDF, internet y YouTube, sin pedir un computador nuevo."
    }
    Slide {
        centeredText: "Al terminar, el sistema queda listo: idioma, teclado, audio, impresoras, controladores de video y wifi se configuran solos."
    }
    Slide {
        centeredText: "Si instalaste sin internet, la configuración final se completa sola la primera vez que el equipo se conecte a una red."
    }

    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() { }
}
