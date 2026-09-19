var Config = new Object();
Config.closeKeys = [27];

// Strings come from Lua (locales/{ar,en}.json, the 'ui.*' subset) on open and on every language switch.
var Strings = {};

function t(key) {
    var value = Strings[key];
    return value === undefined ? key : value;
}

function format(text, args) {
    var i = 0;
    return String(text).replace(/%s/g, function () {
        var v = args[i++];
        return v === undefined ? '' : v;
    });
}

var currentName = '';

function applyStrings(data) {
    if (data.strings) Strings = data.strings;
    var dir = data.dir === 'rtl' ? 'rtl' : 'ltr';
    document.documentElement.setAttribute('dir', dir);
    document.documentElement.setAttribute('lang', data.locale === 'ar' ? 'ar' : 'en');
    document.title = t('ui.title');

    $('[data-i18n]').each(function () {
        $(this).text(t($(this).attr('data-i18n')));
    });
    $('[data-i18n-placeholder]').each(function () {
        $(this).attr('placeholder', t($(this).attr('data-i18n-placeholder')));
    });
    $('#customerWelcome').text(format(t('ui.welcome'), [currentName]));
}

function post(name, payload) {
    $.post('https://w_banking/' + name, JSON.stringify(payload || {}));
}

function showAlert(message, kind) {
    $('#alertMessage').removeClass('alert-success alert-danger').addClass(kind === 'error' ? 'alert-danger' : 'alert-success');
    $('#alertMessage').text(message);
    $('#alertRow').css({ display: 'block' });
}

function hideAlert() {
    $('#alertRow').css({ display: 'none' });
    $('#alertMessage').text('');
}

function hideLocalErrors() {
    $('#withdrawError, #depositError, #transferError, #savingsError').css({ display: 'none' });
    $('#withdrawErrorMsg, #depositErrorMsg, #transferErrorMsg, #savingsErrorMsg').text('');
}

function resetTabs() {
    $('#v-pills-tab .nav-link').removeClass('active').attr('aria-selected', 'false');
    $('#bankingHome-tab').addClass('active').attr('aria-selected', 'true');
    $('#v-pills-tabContent .tab-pane').removeClass('active show');
    $('#bankingHome').addClass('active show');
}

function populateBanking(data) {
    currentName = data.name || '';
    $('#accountName').text(data.name);
    $('#accountNumber').text(data.accountinfo);
    $('#customerWelcome').text(format(t('ui.welcome'), [currentName]));
    $('#currentBalance, #currentBalance1, #currentBalance2').text(data.bankbalance);
    $('#currentCashBalance, #currentCashBalance1, #currentCashBalance2').text(data.cash);
    $('#withdrawAmount, #depositAmount, #transferAmount, #transferAcctNo, #savingsAmount').val('');

    if (data.savings !== undefined && data.savings !== null) {
        $('#savingsBalance').text(data.savings.amount);
        $('#savingAccountCreator').css({ display: 'none' });
        $('#savingsManager').css({ display: 'block' });
    } else {
        $('#savingsBalance').text('');
        $('#savingsManager').css({ display: 'none' });
        $('#savingAccountCreator').css({ display: 'block' });
    }
}

window.addEventListener('message', function (event) {
    var data = event.data;
    if (data.status === 'openbank') {
        // the server sends the refresh and the result message together: keep the alert
        hideLocalErrors();
        resetTabs();
        populateBanking(data.information);
        applyStrings(data);
        $('#bankingContainer').css({ display: 'block' });
    } else if (data.status === 'setLocale') {
        applyStrings(data);
    } else if (data.status === 'closebank') {
        hideAlert();
        hideLocalErrors();
        $('#bankingContainer').css({ display: 'none' });
    } else if (data.status === 'transferError') {
        if (data.error !== undefined) showAlert(data.error, 'error');
    } else if (data.status === 'successMessage') {
        if (data.message !== undefined) showAlert(data.message, 'success');
    }
});

function closeBanking() {
    post('NUIFocusOff');
}

function readAmount(selector) {
    var value = parseInt($(selector).val(), 10);
    return isNaN(value) || value <= 0 ? null : value;
}

function localError(rowSelector, msgSelector, key) {
    $(msgSelector).text(t(key));
    $(rowSelector).css({ display: 'block' });
}

$(function () {
    $('body').on('keydown', function (key) {
        if (Config.closeKeys.includes(key.which)) closeBanking();
    });

    $('#v-pills-tab .nav-link').on('click', function () {
        hideAlert();
        hideLocalErrors();
    });

    $('#openSavings').click(function () {
        post('createSavingsAccount');
    });

    $('#initiateWithdraw').click(function () {
        var amount = readAmount('#withdrawAmount');
        hideLocalErrors();
        if (amount) {
            post('doWithdraw', { amount: amount });
            $('#withdrawAmount').val('');
        } else {
            localError('#withdrawError', '#withdrawErrorMsg', 'ui.withdraw_error');
        }
    });

    $('#initiateDeposit').click(function () {
        var amount = readAmount('#depositAmount');
        hideLocalErrors();
        if (amount) {
            post('doDeposit', { amount: amount });
            $('#depositAmount').val('');
        } else {
            localError('#depositError', '#depositErrorMsg', 'ui.deposit_error');
        }
    });

    $('#initiateTransfer').click(function () {
        var amount = readAmount('#transferAmount');
        var account = ($('#transferAcctNo').val() || '').trim();
        hideLocalErrors();
        if (amount && account.length > 0) {
            post('doTransfer', { amount: amount, account: account });
            $('#transferAmount').val('');
            $('#transferAcctNo').val('');
        } else {
            localError('#transferError', '#transferErrorMsg', 'ui.transfer_error');
        }
    });

    $('#savingsDepositBtn').click(function () {
        var amount = readAmount('#savingsAmount');
        hideLocalErrors();
        if (amount) {
            post('savingsDeposit', { amount: amount });
            $('#savingsAmount').val('');
        } else {
            localError('#savingsError', '#savingsErrorMsg', 'ui.savings_error');
        }
    });

    $('#savingsWithdrawBtn').click(function () {
        var amount = readAmount('#savingsAmount');
        hideLocalErrors();
        if (amount) {
            post('savingsWithdraw', { amount: amount });
            $('#savingsAmount').val('');
        } else {
            localError('#savingsError', '#savingsErrorMsg', 'ui.savings_error');
        }
    });
});
