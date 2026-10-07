// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Simorg

#include "simorg/appmodel/MachineCatalogModel.h"

#include "Support.h"
#include "simorg/client/ServiceSession.h"

#include <QJsonArray>
#include <QStringList>
#include <QUrlQuery>

namespace simorg::app {

using client::ServiceReply;
using support::text;

namespace {

/** A bound or a default the catalogue names; null is "none", which is an invalid QVariant here. */
QVariant optionalValue(const QJsonObject &json, const char *key)
{
    const QJsonValue value = json.value(QLatin1String(key));
    return value.isNull() || value.isUndefined() ? QVariant() : value.toVariant();
}

} // namespace

// ---- AccessField ------------------------------------------------------------------------

AccessField AccessField::fromJson(const QJsonObject &json)
{
    AccessField field;
    field.key = text(json, "key");
    field.label = text(json, "label");
    field.type = text(json, "type");
    field.hint = text(json, "hint");
    field.placeholder = text(json, "placeholder");
    field.required = json.value(QStringLiteral("required")).toBool();
    field.minimum = optionalValue(json, "min");
    field.maximum = optionalValue(json, "max");
    field.defaultValue = optionalValue(json, "default_value");
    for (const QJsonValue &value : json.value(QStringLiteral("options")).toArray()) {
        const QJsonObject option = value.toObject();
        field.options.append({text(option, "value"), text(option, "label"), text(option, "description")});
    }
    for (const QJsonValue &value : json.value(QStringLiteral("fields")).toArray())
        field.fields.append(AccessField::fromJson(value.toObject()));
    const QJsonObject condition = json.value(QStringLiteral("show_when")).toObject();
    field.showWhenField = text(condition, "field");
    field.showWhenEquals = text(condition, "equals");
    field.scope = text(json, "scope");
    field.format = text(json, "format");
    return field;
}

QString AccessField::optionSummary() const
{
    QStringList labels;
    labels.reserve(options.size());
    for (const AccessFieldOption &option : options)
        labels << option.label;
    return labels.join(QStringLiteral(" · "));
}

QString AccessField::labelForValue(const QString &value) const
{
    for (const AccessFieldOption &option : options) {
        if (option.value == value)
            return option.label;
    }
    return value;
}

bool AccessField::appliesTo(const QVariantMap &record, const QList<AccessField> &siblings) const
{
    if (showWhenField.isEmpty())
        return true;
    QVariant held = record.value(showWhenField);
    if (!held.isValid() || held.toString().isEmpty()) {
        // Nothing set counts as the sibling's default, so a record written before the condition existed keeps its
        // meaning.
        for (const AccessField &sibling : siblings) {
            if (sibling.key == showWhenField) {
                held = sibling.defaultValue;
                break;
            }
        }
    }
    return held.toString() == showWhenEquals;
}

QVariantMap AccessField::toVariant() const
{
    QVariantList optionList;
    optionList.reserve(options.size());
    for (const AccessFieldOption &option : options) {
        optionList.append(QVariantMap{{QStringLiteral("value"), option.value},
                                      {QStringLiteral("label"), option.label},
                                      {QStringLiteral("description"), option.description}});
    }
    QStringList rowFieldLabels;
    QVariantList rowFields;
    for (const AccessField &nested : fields) {
        rowFieldLabels << nested.label;
        rowFields.append(nested.toVariant());
    }
    return QVariantMap{
        {QStringLiteral("key"), key},
        {QStringLiteral("label"), label},
        {QStringLiteral("type"), type},
        {QStringLiteral("hint"), hint},
        {QStringLiteral("required"), required},
        {QStringLiteral("options"), optionSummary()},
        {QStringLiteral("optionList"), optionList},
        // Both shapes of the nested fields: the joined labels a summary line wants, and the whole of them for a
        // screen showing values.
        {QStringLiteral("rowFields"), rowFieldLabels.join(QStringLiteral(" · "))},
        {QStringLiteral("fields"), rowFields},
        {QStringLiteral("showWhenField"), showWhenField},
        {QStringLiteral("showWhenEquals"), showWhenEquals},
        {QStringLiteral("scope"), scope},
        {QStringLiteral("format"), format},
        {QStringLiteral("placeholder"), placeholder},
        {QStringLiteral("minimum"), minimum},
        {QStringLiteral("maximum"), maximum},
        {QStringLiteral("defaultValue"), defaultValue},
    };
}

// ---- AccessCategory ---------------------------------------------------------------------

AccessCategory AccessCategory::fromJson(const QJsonObject &json)
{
    AccessCategory category;
    category.key = text(json, "key");
    category.label = text(json, "label");
    category.description = text(json, "description");
    category.deniedBehaviour = text(json, "denied_behaviour");
    category.icon = text(json, "icon");
    category.sensitivity = text(json, "sensitivity");
    const QJsonArray fields =
        json.value(QStringLiteral("schema")).toObject().value(QStringLiteral("fields")).toArray();
    for (const QJsonValue &value : fields)
        category.fields.append(AccessField::fromJson(value.toObject()));
    return category;
}

// ---- AccessCategoryModel ----------------------------------------------------------------

AccessCategoryModel::AccessCategoryModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int AccessCategoryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant AccessCategoryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return {};
    const AccessCategory &category = m_items.at(index.row());
    switch (role) {
    case KeyRole:
        return category.key;
    case LabelRole:
        return category.label;
    case DescriptionRole:
        return category.description;
    case DeniedBehaviourRole:
        return category.deniedBehaviour;
    case IconRole:
        return category.icon;
    case SensitivityRole:
        return category.sensitivity;
    case FieldCountRole:
        return int(category.fields.size());
    case FieldsRole: {
        QVariantList fields;
        fields.reserve(category.fields.size());
        for (const AccessField &field : category.fields)
            fields.append(field.toVariant());
        return fields;
    }
    default:
        return {};
    }
}

QHash<int, QByteArray> AccessCategoryModel::roleNames() const
{
    return {
        {KeyRole, "accessKey"},
        {LabelRole, "label"},
        {DescriptionRole, "description"},
        {DeniedBehaviourRole, "deniedBehaviour"},
        {IconRole, "icon"},
        {SensitivityRole, "sensitivity"},
        {FieldCountRole, "fieldCount"},
        {FieldsRole, "fields"},
    };
}

const AccessCategory *AccessCategoryModel::find(const QString &key) const
{
    for (const AccessCategory &category : m_items) {
        if (category.key == key)
            return &category;
    }
    return nullptr;
}

void AccessCategoryModel::reset(const QList<AccessCategory> &categories)
{
    const bool countMoved = categories.size() != m_items.size();
    beginResetModel();
    m_items = categories;
    endResetModel();
    if (countMoved)
        Q_EMIT countChanged();
}

QVariantMap AccessCategoryModel::at(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= m_items.size())
        return map;
    const QHash<int, QByteArray> names = roleNames();
    for (auto it = names.constBegin(); it != names.constEnd(); ++it)
        map.insert(QString::fromUtf8(it.value()), data(index(row), it.key()));
    return map;
}

// ---- MachineCatalogModel ----------------------------------------------------------------

MachineCatalogModel::MachineCatalogModel(client::ServiceSession *session, QObject *parent)
    : QObject(parent)
    , m_session(session)
    , m_categories(new AccessCategoryModel(this))
{
    connect(m_session, &client::ServiceSession::connected, this, [this] { load(m_category, false); });
    if (m_session->isConnected())
        load(m_category, false);
}

void MachineCatalogModel::refresh(const QString &machineCategoryKey)
{
    load(machineCategoryKey.isEmpty() ? QStringLiteral("DESKTOP") : machineCategoryKey, true);
}

void MachineCatalogModel::load(const QString &category, bool refresh)
{
    m_category = category;
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("category"), category);
    if (refresh)
        query.addQueryItem(QStringLiteral("refresh"), QStringLiteral("true"));

    ++m_loading;
    Q_EMIT stateChanged();
    ServiceReply *reply = m_session->get(QStringLiteral("/v1/machine/catalog"), query);
    connect(reply, &ServiceReply::finished, this, [this, reply, category] {
        --m_loading;
        if (reply->isError()) {
            // What was shown stays: a list from an hour ago is still the list.
            m_lastError = reply->problem().message();
            Q_EMIT stateChanged();
            return;
        }
        const QJsonObject catalog = reply->object();
        if (category != m_category) {
            Q_EMIT stateChanged();
            return; // a later request asked for another kind of machine
        }
        QList<AccessCategory> categories;
        for (const QJsonValue &value : catalog.value(QStringLiteral("items")).toArray())
            categories.append(AccessCategory::fromJson(value.toObject()));
        m_categories->reset(categories);
        m_loaded = true;
        // A stale list is answered with the reason it could not be refreshed.
        m_lastError = catalog.value(QStringLiteral("stale")).toBool()
                          ? support::problemMessage(catalog.value(QStringLiteral("last_error")))
                          : QString();
        Q_EMIT stateChanged();
        Q_EMIT applied();
    });
}

} // namespace simorg::app
