import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Presentation only: the original exception, status and details stay intact.
class UserFacingError {
  const UserFacingError(this.title, this.message);
  final String title;
  final String message;

  static UserFacingError from(Object? error) {
    if (error is TimeoutException || error is http.ClientException) {
      return const UserFacingError('Connection problem',
          'We couldn’t connect to RentHub. Check your connection and try again.');
    }
    if (error is ApiException) {
      final known = <String, String>{
        'KYC_REQUIRED':
            'Verify your MyKad before renting or publishing a listing.',
        'MYKAD_REQUIRED':
            'Verify your MyKad before renting or publishing a listing.',
        'IDENTITY_VERIFICATION_REQUIRED':
            'Verify your identity before continuing.',
        'ITEM_IMAGES_REQUIRED':
            'Add at least three clear photos of the item before submitting.',
        'ITEM_VERIFICATION_REQUIRED':
            'Your item photos need review before this listing can be published.',
        'DRIVING_ELIGIBILITY_REQUIRED':
            'Submit your driving licence for review before renting a vehicle.',
        'DRIVING_ELIGIBILITY_EXPIRED':
            'Update your driving licence verification before renting this vehicle.',
        'DRIVING_ELIGIBILITY_REVIEW_REQUIRED':
            'Your driving licence needs another review before renting this vehicle.',
        'DRIVING_LICENCE_CLASS_REQUIRED':
            'Your approved driving licence does not cover this vehicle’s required class.',
        'UNSUPPORTED_FILE': 'Choose a JPEG, PNG, WebP or supported PDF file.',
        'IMAGE_REQUIRED': 'Choose a JPEG, PNG or WebP photo for this upload.',
        'INVALID_CREDENTIALS': 'The email or password is incorrect.',
        'INVALID_PHOTO':
            'This image cannot be previewed. Choose another photo.',
        'INVALID_RESET_CODE':
            'This reset code is invalid or has expired. Request a new code.',
        'ACCOUNT_RESTRICTED':
            'This account is restricted. Contact support for help.',
        'ACCOUNT_HAS_OPEN_OBLIGATIONS':
            'Finish your ongoing rentals and payments before closing your account.',
        'EMAIL_DELIVERY_FAILED':
            'We couldn’t send the email. Please try again later.',
        'EMAIL_NOT_CONFIGURED':
            'Email is temporarily unavailable. Please try again later.',
        'CATALOG_UNAVAILABLE':
            'Product search is temporarily unavailable. Try again or enter the product manually.',
      };
      if (known.containsKey(error.code)) {
        return UserFacingError('Unable to continue', known[error.code]!);
      }
      if (error.status == 401) {
        return const UserFacingError('Please sign in again',
            'Your session has expired. Sign in again to continue.');
      }
      if (error.status == 403) {
        return const UserFacingError('Access restricted',
            'Your account cannot perform this action. Check your account status or contact support.');
      }
      if (error.status == 429) {
        return const UserFacingError('Please wait',
            'There have been too many attempts. Wait a moment and try again.');
      }
      if (error.status == 413) {
        return const UserFacingError(
            'File too large', 'Choose a smaller file and try again.');
      }
      if (error.status == 409) {
        return const UserFacingError('Something has changed',
            'This action conflicts with an existing record. Refresh and check before trying again.');
      }
      if (error.status == 400 || error.status == 422) {
        final labels = <String, String>{
          'email': 'Email',
          'password': 'Password',
          'displayName': 'Name',
          'phone': 'Phone number',
          'contactNumber': 'Phone number',
          'dailyPrice': 'Daily price',
          'securityDeposit': 'Deposit',
          'itemAgeYears': 'Item age',
          'rentalDurationDays': 'Rental length',
          'title': 'Title',
          'description': 'Description',
          'brand': 'Brand',
          'productModel': 'Model',
          'location': 'Location',
          'postcode': 'Postcode',
          'code': 'Reset code',
          'startDate': 'Start date',
          'endDate': 'End date',
        };
        final details = error.details;
        final fields = details is List
            ? details
                .whereType<Map>()
                .map((item) => labels[item['field']])
                .whereType<String>()
                .toSet()
            : <String>{};
        return UserFacingError(
            'Check your details',
            fields.isEmpty
                ? 'Some details are invalid. Check the form and try again.'
                : 'Please check: ${fields.join(', ')}.');
      }
      if (error.status >= 500) {
        return const UserFacingError('Temporarily unavailable',
            'RentHub couldn’t complete this request. Please try again later.');
      }
      if (error.status == 404) {
        return const UserFacingError('Not available',
            'This information is no longer available. Refresh and try again.');
      }
    }
    // Some platform/auth SDK failures are not HTTP exceptions. Classify only;
    // never forward their text (which may contain URLs or credentials).
    final text = error.toString().toLowerCase();
    if (text.contains('socketexception') || text.contains('network_error')) {
      return const UserFacingError('Connection problem',
          'We couldn’t connect to RentHub. Check your connection and try again.');
    }
    if (text.contains('cancelled') || text.contains('canceled')) {
      return const UserFacingError('Sign-in cancelled',
          'Sign-in was cancelled. You can try again when you’re ready.');
    }
    return const UserFacingError(
        'Unable to continue', 'Something went wrong. Please try again.');
  }
}

String friendlyError(Object? error) => UserFacingError.from(error).message;
