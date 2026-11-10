#pragma once

#include <QObject>
#include <QString>

namespace catchypills::itsm {

/**
 * Coordinates ServiceNow KB HTML capture notifications and formats template
 * refactoring prompts directly onto the Wayland clipboard.
 */
class ITSMController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isHtmlReady READ isHtmlReady NOTIFY isHtmlReadyChanged)
    Q_PROPERTY(QString storedHtml READ storedHtml NOTIFY storedHtmlChanged)
    Q_PROPERTY(int htmlLength READ htmlLength NOTIFY storedHtmlChanged)
    Q_PROPERTY(QString lastTemplateName READ lastTemplateName NOTIFY lastTemplateNameChanged)

public:
    explicit ITSMController(QObject *parent = nullptr);

    bool isHtmlReady() const noexcept { return m_isHtmlReady; }
    QString storedHtml() const { return m_storedHtml; }
    int htmlLength() const noexcept { return static_cast<int>(m_storedHtml.size()); }
    QString lastTemplateName() const { return m_lastTemplateName; }

    Q_INVOKABLE void generatePrompt(const QString &templateName);
    Q_INVOKABLE void clearReady();

public Q_SLOTS:
    void setHtmlReady(const QString &htmlText);

Q_SIGNALS:
    void isHtmlReadyChanged();
    void storedHtmlChanged();
    void lastTemplateNameChanged();

private:
    bool m_isHtmlReady{false};
    QString m_storedHtml;
    QString m_lastTemplateName;
    QString m_lastGeneratedPrompt;
};

} // namespace catchypills::itsm
