"""Reviewed object-type routing, not trained labels or authenticity evidence.

Keep unsupported types explicit. In particular, a TV/screen is not a monitor,
and a generic scooter/tent does not establish a mobility/camping subtype.
"""

TYPE_CONTRACT = 'renthub-item-types-v1'
PRODUCT_TYPES = {
    'devices': {
        'smartphones': {'smartphone': {'cell phone', 'mobile phone', 'smartphone', 'phone'}},
        'cameras': {'camera': {'camera', 'cameras', 'digital camera', 'mirrorless camera', 'dslr'},
                    'camera_lens': {'camera lens', 'photographic lens'}},
        'computers': {'laptop': {'laptop', 'notebook computer'},
                      'desktop': {'computer', 'desktop', 'desktop computer'},
                      'mouse': {'mouse', 'computer mouse'},
                      'keyboard': {'keyboard', 'computer keyboard'},
                      'monitor': {'computer monitor'}},
        'audio': {'speaker': {'speaker', 'loudspeaker'},
                  'headphones': {'headphones', 'headphone', 'earphones', 'earbuds'},
                  'microphone': {'microphone'}, 'amplifier': {'amplifier'},
                  'audio_mixer': {'audio mixer', 'mixing console'}},
        'gaming': {'console': {'game console', 'gaming console', 'console'},
                   'controller': {'game controller', 'gaming controller'},
                   'vr_headset': {'vr headset', 'virtual reality headset'}},
        'other devices': {'television': {'tv', 'television'}, 'projector': {'projector'},
                          'tablet': {'tablet'}, 'printer': {'printer'},
                          'walkie_talkie': {'walkie talkie', 'two way radio'},
                          'video_capture': {'video capture device'},
                          'smartwatch': {'smartwatch', 'smart watch'}},
    },
    'vehicles': {
        'cars': {'car': {'car', 'cars', 'automobile', 'sedan', 'suv', 'hatchback'}},
        'motorcycles': {'motorcycle': {'motorcycle', 'motorbike', 'scooter'}},
        'bicycles': {'bicycle': {'bicycle', 'cycle'}},
        'other vehicles': {'electric_scooter': {'electric scooter', 'kick scooter'},
                           'mobility_scooter': {'mobility scooter'},
                           'electric_unicycle': {'electric unicycle'},
                           # Preserve existing review support for legacy listings.
                           'truck': {'truck'}, 'bus': {'bus'}, 'van': {'van'}, 'boat': {'boat'}},
    },
    'equipment': {
        'tools': {'drill': {'drill', 'power drill'}, 'hammer': {'hammer'},
                  'saw': {'saw', 'power saw'}, 'wrench': {'wrench'},
                  'screwdriver': {'screwdriver'}, 'ladder': {'ladder'},
                  'sander': {'sander'}, 'grinder': {'grinder'}, 'power_tool': {'power tool'}},
        'sports equipment': {'racket': {'tennis racket', 'racket', 'badminton racket'},
                             'sports_ball': {'sports ball'}, 'baseball_bat': {'baseball bat'},
                             'baseball_glove': {'baseball glove'}, 'skateboard': {'skateboard'},
                             'surfboard': {'surfboard'}, 'skis': {'skis'}, 'snowboard': {'snowboard'},
                             'bicycle': {'bicycle'}, 'kayak': {'kayak'}, 'dumbbell': {'dumbbell'},
                             'camping_tent': {'camping tent'}, 'sleeping_bag': {'sleeping bag'},
                             'golf_clubs': {'golf clubs'}, 'paddleboard': {'paddleboard'},
                             'life_jacket': {'life jacket'}, 'snorkel_set': {'snorkel set'},
                             'fitness_equipment': {'treadmill', 'exercise bike', 'rowing machine'}},
        'event equipment': {'event_chair': {'chair'}, 'event_table': {'dining table', 'table'},
                            'event_tent': {'tent', 'canopy'}, 'projector': {'projector'},
                            'speaker': {'speaker'}, 'lighting': {'stage light'},
                            'television': {'tv', 'television'}, 'audio_mixer': {'audio mixer'},
                            'tripod': {'tripod'}, 'pa_set': {'pa system'}},
        'other equipment': {'generator': {'generator'}, 'ladder': {'ladder'},
                            'pressure_washer': {'pressure washer'}, 'vacuum': {'vacuum cleaner'},
                            'fabric_cleaner': {'carpet extractor', 'fabric cleaner'}},
    },
    'books': {key: {'book': {'book', 'books'}} for key in
              ('textbooks', 'reference books', 'fiction', 'other books')},
    'clothing': {
        'formal wear': {'suit': {'suit', 'tuxedo'}, 'formal_jacket': {'blazer', 'formal jacket'},
                        'formal_dress': {'dress', 'gown'}, 'formal_wear': {'formal wear'}},
        'costumes': {'costume': {'costume', 'costumes'}},
        'traditional wear': {'malay_traditional': {'baju melayu', 'baju kurung', 'kebaya'},
                             'sari': {'sari'}, 'hanfu': {'hanfu'}, 'kurta': {'kurta', 'sherwani'},
                             'traditional_costume': {'traditional costume'}},
        'other clothing': {'winter_garment': {'coat', 'jacket', 'winter coat'},
                           'rainwear': {'raincoat', 'poncho'}, 'garment': {'clothing', 'shirt'}},
    },
}

# Existing category-only callers retain the union. Known catalogue types narrow
# that union; unknown types must not silently fall back to another object's labels.
DOMAINS = {category: {subcategory: set().union(*types.values())
                      for subcategory, types in subcategories.items()}
           for category, subcategories in PRODUCT_TYPES.items()}
