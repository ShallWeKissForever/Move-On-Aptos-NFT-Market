module nftmarket::mynft{
    use std::option;
    use std::signer;
    use std::signer::address_of;
    use std::string;
    use aptos_std::smart_table;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::object::{Object};
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

    struct TokenRefsStore has key {
        transfer_ref: object::LinearTransferRef,
        burn_ref: token::BurnRef
    }

    struct Content has key {
        content: string::String
    }

    struct Orders has key, store, drop, copy {
        orders: smart_table::SmartTable<u64, Order>,
        order_counter: u64
    }

    #[event]
    struct Order has store, drop, copy {
        seller: address,
        price: u64,
        token: address,
        completed: bool
    }

    #[event]
    struct MintEvent has drop, store {
        owner: address,
        token: address,
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

    #[event]
    struct TransferEvent has drop, store {
        sender: &signer,
        reciver: address,
        amount: u64,
        tokenId: address
    }

    #[event]
    struct ChangePrice has drop, store {
        seller: address,
        token: address,
        old_price: u64,
        new_price: u64
    }

    fun init_module(sender: &signer) {

        let (resource_signer, resource_cap) = account::create_resource_account(
            sender, RESOURCECAPSEED
        );

        move_to(&resource_signer, ResourceCap{ cap:resource_cap });

        collection::create_unlimited_collection(
            &resource_signer,
            string::utf8(CollectionDescription),
            string::utf8(CollectionName),
            option::none(),
            string::utf8(CollectionURI)
        );

        let orders = Orders{
            orders: smart_table::new(),
            order_counter: 0
        };

        move_to(sender, orders);

    }

    entry public fun mint(sender: &signer, content: string::String) acquires ResourceCap {

        let resource_cap = &borrow_global<ResourceCap>(account::create_resource_address(
            &@nftmarket, RESOURCECAPSEED
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
            transfer_ref: object::generate_linear_transfer_ref( &object::generate_transfer_ref(&token_ref) ),
            burn_ref: token::generate_burn_ref(&token_ref)
        });
        move_to(&token_signer, Content{ content });

        event::emit(
            MintEvent{
                owner: signer::address_of(sender),
                token: object::address_from_constructor_ref(&token_ref),
                content
            }
        );

        object::transfer(
            resource_signer,
            object::object_from_constructor_ref<Token>(&token_ref),
            signer::address_of(sender),
        );

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
        let TokenRefsStore{ transfer_ref: _,  burn_ref } = move_from<TokenRefsStore>(object::object_address(&token));
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

    entry fun transfer(buyer: &signer, celler: address, amount: u64, token: address) acquires TokenRefsStore {
        assert!(coin::balance<AptosCoin>(signer::address_of(buyer)) >= amount, 2);

        //transfer APT from buyer to celler
        coin::transfer<AptosCoin>(buyer, celler, amount);
        //transfer token from celler to buyer
        object::transfer_with_ref( borrow_global<TokenRefsStore>(token).transfer_ref, address_of(buyer) );

        event::emit(
            TransferEvent{
                sender: buyer,
                reciver: celler,
                amount,
                tokenId: token
            }
        );

    }

    entry fun createOrder(sender: &signer, token:address, price: u64) acquires Orders {

        let orders = borrow_global_mut<Orders>(@nftmarket);
        let new_order = Order{
            seller: address_of(sender),
            price,
            token,
            completed: false
        };
        smart_table::upsert(&mut orders.orders, orders.order_counter+1, new_order);
        orders.order_counter = orders.order_counter + 1;

        event::emit(
            new_order
        )
    }

    entry fun changePrice(order_counter: u64, new_price: u64) acquires Orders {

        let orders = borrow_global_mut<Orders>( @nftmarket ).orders;
        let order = smart_table::borrow_mut(&mut orders, order_counter);

        let old_price = order.price;
        order.price = new_price;

        event::emit(
            ChangePrice{
                seller: order.seller,
                token: order.token,
                old_price: old_price,
                new_price
            }
        );

    }

    entry fun cancelOrder() {

    }

}