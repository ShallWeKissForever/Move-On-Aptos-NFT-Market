module mynft::mynft{
    use std::option;
    use std::signer;
    use std::string;
    use std::string::utf8;
    use aptos_std::debug::print;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    const RESOURCECAPSEED : vector<u8> = b"Gauss";

    const CollectionDescription: vector<u8> = b"gauss nft test";

    const CollectionName: vector<u8> = b"gauss";

    const CollectionURI: vector<u8> = b"https://s21.ax1x.com/2024/03/11/pF6AjBD.jpg";

    const TokenURI: vector<u8> = b"https://s21.ax1x.com/2024/03/11/pF6AjBD.jpg";

    const TokenPrefix: vector<u8> = b"Gauss #";

    struct ResourceCap has key {
        cap: SignerCapability
    }

    struct CollectionRefsStore has key {
        mutator_ref: collection::MutatorRef
    }

    struct TokenRefsStore has key {
        extend_ref: object::ExtendRef,
        burn_ref: token::BurnRef
    }

    struct Content has key {
        content: string::String
    }

    #[event]
    struct MintEvent has drop, store {
        owner: address,
        tokenId: address,
        content: string::String
    }

    #[event]
    struct ModifyEvent has drop,store {
        owner: address,
        tokenId: address,
        old_content: string::String,
        new_content: string::String
    }

    #[event]
    struct BurnEvent has drop, store {
        owner: address,
        tokenId: address,
        content: string::String
    }

    fun init_module(sender: &signer) {

        let (resource_signer, resource_cap) = account::create_resource_account(
            sender, RESOURCECAPSEED
        );

        move_to(&resource_signer, ResourceCap{ cap:resource_cap });

        let collection_ref = collection::create_unlimited_collection(
            &resource_signer,
            string::utf8(CollectionDescription),
            string::utf8(CollectionName),
            option::none(),
            string::utf8(CollectionURI)
        );

        let collection_signer = object::generate_signer(&collection_ref);

        let mutator_ref = collection::generate_mutator_ref(&collection_ref);

        move_to(
            &collection_signer,
            CollectionRefsStore {
                mutator_ref
            }
        );

    }

    entry public fun mint(sender: &signer, content: string::String) acquires ResourceCap {

        let resource_cap = &borrow_global<ResourceCap>(account::create_resource_address(
            &@mynft, RESOURCECAPSEED
        )).cap;
        let resource_signer = &account::create_signer_with_capability(resource_cap);

        let token_ref = token::create_numbered_token(
            resource_signer,
            string::utf8(CollectionName),
            string::utf8(CollectionDescription),
            string::utf8(TokenPrefix),
            string::utf8(b""),
            option::none(),
            string::utf8(TokenURI),
        );

        let token_signer = object::generate_signer(&token_ref);

        move_to(&token_signer, TokenRefsStore{
            extend_ref: object::generate_extend_ref(&token_ref),
            burn_ref: token::generate_burn_ref(&token_ref)
        });
        move_to(&token_signer, Content{ content });

        event::emit(
            MintEvent{
                owner: signer::address_of(sender),
                tokenId: object::address_from_constructor_ref(&token_ref),
                content
            }
        );

        object::transfer(
            resource_signer,
            object::object_from_constructor_ref<Token>(&token_ref),
            signer::address_of(sender),
        )
    }

    entry fun modify(sender: &signer, token: Object<Content>, content: string::String) acquires Content {
        assert!(object::is_owner(token, signer::address_of(sender)), 1);
        let old_content = borrow_global<Content>(object::object_address(&token)).content;

        event::emit(
            ModifyEvent{
                owner: object::owner(token),
                tokenId: object::object_address(&token),
                old_content,
                new_content: content
            }
        );

        borrow_global_mut<Content>(object::object_address(&token)).content = content;
    }

    entry fun burn(sender: &signer, token: Object<Content>) acquires TokenRefsStore, Content {
        assert!(object::is_owner(token, signer::address_of(sender)), 1);
        let TokenRefsStore{ extend_ref: _, burn_ref } = move_from<TokenRefsStore>(object::object_address(&token));
        let Content { content } = move_from<Content>(object::object_address(&token));

        event::emit(
            BurnEvent{
                owner: signer::address_of(sender),
                tokenId: object::object_address(&token),
                content
            }
        );

        token::burn(burn_ref);
    }

}